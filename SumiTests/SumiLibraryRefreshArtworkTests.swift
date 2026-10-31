@testable import Sumi
import Foundation
import AidokuRunner
import Combine
import Testing

@MainActor
@Suite(.serialized)
struct SumiLibraryRefreshArtworkTests {
    @Test("Metadata and library membership refresh without rerunning the initial cover cohort")
    func refreshKeepsArtworkIndependent() async {
        let state = SnapshotState()
        let store = SumiLibraryStore(searchSourceLoader: { [] }, coverPreparer: { _ in await state.prepared() },
            snapshotLoader: { state.snapshot })
        await store.refresh()
        #expect(state.preparations == 1)
        #expect(store.library == state.snapshot.saved)

        var renamed = state.snapshot.saved[0].manga
        renamed.title = "Updated title"
        let changed = SumiBook(manga: renamed, chapterLabel: "Chapter 2", pageLabel: "Page 6", progress: 0.5, isInLibrary: true)
        let added = SumiBook(manga: .init(sourceKey: "refresh-artwork-test", key: "second", title: "New book",
            cover: "https://example.com/new-cover.jpg"), isInLibrary: true)
        state.snapshot = .init(saved: [changed, added], recent: [changed])
        await store.refresh()
        #expect(store.library == [changed, added])
        #expect(store.recentlyRead == [changed])
        #expect(store.loadState == .loaded)
        #expect(state.preparations == 1, "Visible tiles load new artwork without preloading the entire library again")

        renamed.cover = "https://example.com/revised-cover.jpg"
        state.snapshot = .init(saved: [SumiBook(manga: renamed, isInLibrary: true)], recent: [])
        await store.refresh()
        #expect(store.library == state.snapshot.saved)
        #expect(state.preparations == 1)
    }

    @Test("An unchanged library snapshot is not republished on foreground or return refresh")
    func unchangedRefreshDoesNotReplaceTheLibrary() async {
        let state = SnapshotState()
        let store = SumiLibraryStore(searchSourceLoader: { [] }, coverPreparer: { _ in await state.prepared() },
            snapshotLoader: { state.snapshot })
        var publications = 0
        let subscription = store.$library.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel() }
        await store.refresh()
        #expect(publications == 1)
        await store.refresh()
        await store.refresh()
        #expect(await store.refreshForReturn())
        #expect(publications == 1)
        #expect(state.preparations == 1)
    }

    @Test("Cloud-restored bundled cover paths resolve locally without changing library metadata or the synced snapshot")
    func restoredBundledCoversAreLocal() async throws {
        let oldRoot = "file:///var/mobile/Containers/Data/Application/00000000-0000-0000-0000-000000000001/Library/Application%20Support/"
        let paths = [(HonbakoTutorialManga.mangaKey, "HonbakoTutorial/v3/en/cover.png")]
            + HonbakoGuideBook.allCases.map { ($0.rawValue, "HonbakoGuides/v5/\($0.rawValue)/en/cover.png") }
        let original = paths.map { key, path in
            SumiBook(manga: .init(sourceKey: HonbakoTutorialManga.sourceKey, key: key, title: "Preserved title", cover: oldRoot + path),
                     chapterLabel: "Chapter 1", pageLabel: "Page 2", progress: 0.5, isInLibrary: true, lastReadPage: 2)
        }
        let snapshot = SumiLibrarySnapshot(saved: original, recent: original)
        let store = SumiLibraryStore(searchSourceLoader: { [] }, coverPreparer: { _ in }, snapshotLoader: { snapshot })
        await store.refresh()
        #expect(store.library.count == original.count)
        for (restored, old) in zip(store.library, original) {
            let url = try #require(restored.coverURL)
            #expect(url.isFileURL)
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(url != old.coverURL)
            #expect(restored.id == old.id)
            #expect(restored.title == old.title)
            #expect(restored.lastReadPage == old.lastReadPage)
            #expect(restored.progress == old.progress)
        }
        #expect(store.recentlyRead == store.library)
        #expect(snapshot.saved == original, "Resolving local assets must not replace the CloudKit records or save a new device-specific path")
        let local = store.library
        await store.refresh()
        #expect(store.library == local, "Ordinary refreshes must retain the same artwork identity")
    }

    @Test("Cover recovery never rebases arbitrary file paths, other sources, unknown guide IDs, or mismatched guide assets")
    func unrelatedLocalCoversStayUnchanged() throws {
        let prefix = "file:///var/mobile/Containers/Data/Application/00000000-0000-0000-0000-000000000001/Library/Application%20Support/"
        for (source, key, cover) in [
            ("personal.collection", "guide-find", prefix + "HonbakoGuides/v5/guide-find/en/cover.png"),
            (HonbakoTutorialManga.sourceKey, "unknown-book", prefix + "HonbakoGuides/v5/guide-find/en/cover.png"),
            (HonbakoTutorialManga.sourceKey, "guide-read", prefix + "HonbakoGuides/v5/guide-find/en/cover.png"),
            (HonbakoTutorialManga.sourceKey, "guide-find", "file:///private/user-collection/cover.png"),
            (HonbakoTutorialManga.sourceKey, "guide-find", prefix + "HonbakoGuides/v5/guide-find/unknown-language/cover.png"),
            (HonbakoTutorialManga.sourceKey, "guide-find", "https://cdn.example.com/cover.png")
        ] {
            let manga = AidokuRunner.Manga(sourceKey: source, key: key, title: "Custom", cover: cover)
            #expect(try HonbakoTutorialManga.restoredCoverURL(for: manga) == nil)
        }
    }

    @MainActor
    private final class SnapshotState {
        var preparations = 0
        var snapshot = SumiLibrarySnapshot(saved: [SumiBook(manga: AidokuRunner.Manga(
            sourceKey: "refresh-artwork-test", key: "first", title: "Original title",
            cover: "https://example.com/original-cover.jpg"), isInLibrary: true)], recent: [])
        func prepared() { preparations += 1 }
    }
}
