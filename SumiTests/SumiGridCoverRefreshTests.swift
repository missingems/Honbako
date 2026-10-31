@testable import Sumi
import AidokuRunner
import Nuke
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiGridCoverRefreshTests {
    @Test("A metadata refresh keeps the visible print after cache eviction, while a new cover URL updates only its book")
    func metadataPreservesTheVisibleCover() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "HonbakoGridCoverRefresh-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appending(path: "first.png")
        let secondURL = directory.appending(path: "second.png")
        for (url, color) in [(firstURL, UIColor.blue), (secondURL, UIColor.red)] {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30)).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
            }
            try #require(image.pngData()).write(to: url)
        }
        let sourceKey = "grid-cover-refresh-\(UUID())"
        var manga = AidokuRunner.Manga(sourceKey: sourceKey, key: "first", title: "Original title", cover: firstURL.absoluteString)
        let original = SumiBook(manga: manga, isInLibrary: true)
        let loader = SumiCoverArtworkLoader()
        let loaded = try #require(await loader.loadCover(for: original))
        let request = try #require(await loader.coverRequest(for: original))
        let tile = SumiGridBookView(frame: CGRect(x: 0, y: 0, width: 136, height: 200), artworkLoader: loader)
        tile.configure(book: original)
        #expect(tile.image === loaded)

        // Evict only this loader's decoded copies and this unique Nuke entry.
        // A visible tile still owns its original UIImage through memory pressure.
        loader.releaseDecodedCoversForMemoryPressure()
        ImagePipeline.shared.cache.removeCachedImage(for: request, caches: [.memory])
        #expect(loader.cachedCover(for: original) == nil)
        manga.title = "Renamed title"
        let refreshed = SumiBook(manga: manga, chapterLabel: "Chapter 2", pageLabel: "Page 6", progress: 0.5, isInLibrary: true)
        tile.configure(book: refreshed)
        tile.layoutIfNeeded()
        #expect(tile.image === loaded, "Renaming or updating progress cannot replace an existing print with a placeholder")
        #expect(tile.coverArtwork === loaded)

        let other = SumiBook(manga: .init(sourceKey: sourceKey, key: "second", title: "Other book", cover: firstURL.absoluteString))
        let otherCover = try #require(await loader.loadCover(for: other))
        manga.cover = secondURL.absoluteString
        let revised = SumiBook(manga: manga, isInLibrary: true)
        let revisedCover = try #require(await loader.loadCover(for: revised))
        tile.configure(book: revised)
        #expect(tile.image === revisedCover)
        #expect(tile.image !== loaded)
        #expect(loader.cachedCover(for: other) === otherCover, "Changing one cover must not invalidate its neighbours")
    }

    @Test("Restoring a source retries its waiting cover and retains every unrelated decoded image")
    func sourceRestorationRetriesOnlyMissingArtwork() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "HonbakoRestoredSourceCover-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appending(path: "cover.png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
        try #require(image.pngData()).write(to: imageURL)
        let loader = SumiCoverArtworkLoader()
        let unrelated = SumiBook(manga: .init(sourceKey: "retained-neighbour-\(UUID())", key: "other", title: "Other", cover: imageURL.absoluteString))
        let retained = try #require(await loader.loadCover(for: unrelated))
        let key = "restored-private-source-\(UUID())"
        let book = SumiBook(manga: .init(sourceKey: key, key: "restored", title: "Restored book", cover: "http://192.168.1.4/cover.jpg"), isInLibrary: true)
        #expect(await loader.coverRequest(for: book) == nil)
        loader.recordVisibleFailure(for: book)
        let tile = SumiGridBookView(frame: CGRect(x: 0, y: 0, width: 136, height: 200), artworkLoader: loader)
        tile.configure(book: book)
        tile.layoutIfNeeded()
        let placeholder = tile.image
        let runner = RestoredCoverRunner(imageURL: imageURL)
        let source = AidokuRunner.Source(key: key, name: "Restored server", version: 1, contentRating: .safe, runner: runner)
        var sources = SourceStore.shared.sourcesByKey
        sources[key] = source
        SourceStore.shared.update(sourcesByKey: sources, disabledSourceKeys: SourceStore.shared.disabledSourceKeys)
        defer {
            var current = SourceStore.shared.sourcesByKey
            current[key] = nil
            SourceStore.shared.update(sourcesByKey: current, disabledSourceKeys: SourceStore.shared.disabledSourceKeys)
        }
        NotificationCenter.default.post(name: .sourceLoaded, object: key)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while loader.cachedCover(for: book) == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let restoredCover = try #require(loader.cachedCover(for: book))
        #expect(tile.image === restoredCover)
        #expect(tile.image !== placeholder)
        #expect(await runner.count == 1, "Only the restored source builds its authenticated image request")
        #expect(loader.cachedCover(for: unrelated) === retained, "Restoring a source must not invalidate unrelated artwork")
        #expect(!loader.isInFailureCooldown(for: book))
        NotificationCenter.default.post(name: .sourceLoaded, object: key)
        try await Task.sleep(for: .milliseconds(20))
        #expect(tile.image === restoredCover)
        #expect(await runner.count == 1, "Repeated source publication must not reload an already displayed cover")
    }

    @Test("Generated placeholder text can update without treating metadata as a new cover image")
    func placeholderReflectsTheEditedTitle() throws {
        var manga = AidokuRunner.Manga(sourceKey: "grid-placeholder-refresh", key: "first", title: "First title")
        let tile = SumiGridBookView(frame: CGRect(x: 0, y: 0, width: 136, height: 200), artworkLoader: SumiCoverArtworkLoader())
        tile.configure(book: SumiBook(manga: manga))
        tile.layoutIfNeeded()
        let first = try #require(tile.image)
        manga.title = "Second title"
        tile.configure(book: SumiBook(manga: manga))
        tile.layoutIfNeeded()
        #expect(tile.image != nil)
        #expect(tile.image !== first)
    }

    private actor RestoredCoverRunner: AidokuRunner.Runner {
        nonisolated let features = AidokuRunner.SourceFeatures(providesImageRequests: true)
        let imageURL: URL
        var count = 0
        init(imageURL: URL) { self.imageURL = imageURL }
        func getImageRequest(url: String, context: AidokuRunner.PageContext?) async throws -> URLRequest {
            count += 1
            var request = URLRequest(url: imageURL)
            request.setValue("Fixture-Only", forHTTPHeaderField: "Authorization")
            return request
        }
        func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult { .init(entries: [], hasNextPage: false) }
        func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga { manga }
        func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] { [] }
    }
}
