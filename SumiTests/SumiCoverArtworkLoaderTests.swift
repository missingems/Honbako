@testable import Sumi
import AidokuRunner
import Foundation
import Testing
import UIKit

@MainActor
struct SumiCoverArtworkLoaderTests {
    @Test("A source warms its covers as a bounded batch before returning")
    func boundedBatch() async {
        let state = WorkState()
        let loader = SumiCoverArtworkLoader(concurrency: 2) { _ in
            state.begin()
            try? await Task.sleep(for: .milliseconds(10))
            state.end()
        }
        await loader.prepare(books(7))
        #expect(state.count == 7)
        #expect(state.active == 0)
        #expect(state.maximum <= 2)
    }

    @Test("A noncooperative cover host cannot block publication beyond the batch deadline")
    func deadlineKeepsStablePlaceholder() async throws {
        let gate = Gate()
        let candidates = books(1)
        let loader = SumiCoverArtworkLoader(timeout: .milliseconds(30)) { _ in await gate.wait() }
        let completion = WorkState()
        let task = Task { await loader.prepare(candidates); completion.count += 1 }
        defer { task.cancel(); gate.release() }
        try await wait { gate.started }
        try await wait { completion.count == 1 }
        #expect(loader.usesPreparedPlaceholder(for: candidates[0]))
        gate.release()
        await task.value
    }

    @Test("Cancelling a query stops its wait and does not cache a failed-cover placeholder")
    func cancellationDoesNotPoisonRetry() async throws {
        let gate = Gate()
        let candidates = books(1)
        let loader = SumiCoverArtworkLoader(timeout: .seconds(5)) { _ in await gate.wait() }
        let completion = WorkState()
        let task = Task { await loader.prepare(candidates); completion.count += 1 }
        defer { task.cancel(); gate.release() }
        try await wait { gate.started }
        task.cancel()
        try await wait { completion.count == 1 }
        #expect(!loader.usesPreparedPlaceholder(for: candidates[0]))
        gate.release()
        await task.value
    }

    @Test("A resolved source outside SourceStore uses the same modified-image cache for warming and synchronous tile lookup")
    func resolvedSourceCacheIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "HonbakoCoverCache-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appending(path: "cover.png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
        try #require(image.pngData()).write(to: imageURL)
        let key = "unregistered-cover-source-\(UUID())"
        let runner = CoverRunner(imageURL: imageURL)
        var source: AidokuRunner.Source? = .init(key: key, name: "Fixture", version: 1,
            contentRating: .safe, runner: runner)
        weak var retainedSource = source
        let book = SumiBook(manga: .init(sourceKey: key, key: "manga", title: "Manga",
            cover: "https://example.com/needs-source-header.png"))
        let loader = SumiCoverArtworkLoader()
        #expect(SourceStore.shared.source(for: key) == nil)
        let loaded = await loader.loadCover(for: book, source: source)
        try #require(loaded != nil)
        source = nil
        #expect(retainedSource != nil, "The cached source identity must not become a reusable dangling address")
        #expect(loader.cachedCover(for: book) === loaded)
        #expect(!loader.usesPreparedPlaceholder(for: book))
        #expect(await runner.count == 1)
        #expect(await loader.loadCover(for: book, source: retainedSource) === loaded)
        #expect(await runner.count == 1)
    }

    private func books(_ count: Int) -> [SumiBook] {
        (0..<count).map { SumiBook(manga: .init(sourceKey: "cover-batch-\(UUID())", key: String($0),
            title: "Manga \($0)", cover: "https://example.com/\($0).jpg")) }
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(predicate())
    }

    @MainActor private final class WorkState {
        var count = 0
        var active = 0
        var maximum = 0
        func begin() { count += 1; active += 1; maximum = max(maximum, active) }
        func end() { active -= 1 }
    }

    @MainActor private final class Gate {
        var started = false
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false
        func wait() async {
            started = true
            if released { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func release() { released = true; continuation?.resume(); continuation = nil }
    }

    private actor CoverRunner: AidokuRunner.Runner {
        nonisolated let features = AidokuRunner.SourceFeatures(providesImageRequests: true)
        let imageURL: URL
        var count = 0
        init(imageURL: URL) { self.imageURL = imageURL }
        func getImageRequest(url: String, context: AidokuRunner.PageContext?) async throws -> URLRequest {
            count += 1
            var request = URLRequest(url: imageURL)
            request.setValue("Honbako-Fixture", forHTTPHeaderField: "User-Agent")
            request.setValue("Required", forHTTPHeaderField: "X-Source-Fixture")
            return request
        }
        func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
            .init(entries: [], hasNextPage: false)
        }
        func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga { manga }
        func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] { [] }
    }
}
