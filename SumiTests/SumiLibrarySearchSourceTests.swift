@testable import Sumi
import AidokuRunner
import Foundation
import Testing

@MainActor
struct SumiLibrarySearchSourceTests {
    @Test("Removing a source prevents its delayed search response from restoring rows")
    func removedSourceCannotRepublish() async throws {
        let key = "removed-search-\(UUID().uuidString)"
        let gate = SearchGate()
        let source = source(key: key, gate: gate)
        let store = SumiLibraryStore(searchSourceLoader: { [source] })
        defer { store.cancelSearch(); Task { await gate.release() } }
        store.search(query: "Manga")
        try await wait { await gate.started }
        NotificationCenter.default.post(name: .sourceUnloaded, object: key)
        // Deliver the MainActor notification before the uncooperative provider.
        try await Task.sleep(for: .milliseconds(20))
        await gate.release()
        try await wait { !store.isSearching }
        #expect(store.searchResults.isEmpty)
        #expect(store.searchSections.isEmpty)
        #expect(store.providerFailures[key] == nil)
    }

    @Test("Removing one visible source preserves the other source's rows and header")
    func pruneOnlyRemovedSource() async throws {
        let firstKey = "first-search-\(UUID().uuidString)"
        let otherKey = "other-search-\(UUID().uuidString)"
        let first = source(key: firstKey)
        let other = source(key: otherKey)
        let store = SumiLibraryStore(searchSourceLoader: { [first, other] })
        defer { store.cancelSearch() }
        store.search(query: "Manga")
        try await wait { !store.isSearching && store.searchResults.count == 2 }
        #expect(Set(store.searchSections.map(\.sourceKey)) == [firstKey, otherKey])
        NotificationCenter.default.post(name: .sourceUnloaded, object: firstKey)
        try await wait { store.searchResults.count == 1 }
        #expect(store.searchResults.first?.sourceKey == otherKey)
        #expect(store.searchSections.map(\.sourceKey) == [otherKey])
    }

    private func source(key: String, gate: SearchGate? = nil) -> AidokuRunner.Source {
        let manga = AidokuRunner.Manga(sourceKey: key, key: "manga", title: "Shared Manga",
            cover: "https://example.com/cover.jpg", authors: ["Author"], status: .ongoing,
            chapters: [.init(key: "chapter", language: "en")])
        return .init(key: key, name: key, version: 1, languages: ["en"], contentRating: .safe,
                     runner: SearchRunner(manga: manga, gate: gate))
    }

    private func wait(_ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await predicate()), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(await predicate())
    }

    private actor SearchGate {
        private(set) var started = false
        private var released = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async {
            started = true
            if released { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func release() { released = true; continuation?.resume(); continuation = nil }
    }

    private actor SearchRunner: AidokuRunner.Runner {
        nonisolated let features = AidokuRunner.SourceFeatures(providesListings: true)
        let manga: AidokuRunner.Manga
        let gate: SearchGate?
        init(manga: AidokuRunner.Manga, gate: SearchGate?) { self.manga = manga; self.gate = gate }
        func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
            await gate?.wait()
            return .init(entries: [manga], hasNextPage: false)
        }
        func getMangaList(listing: AidokuRunner.Listing, page: Int) async throws -> AidokuRunner.MangaPageResult {
            .init(entries: [manga], hasNextPage: false)
        }
        func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga { manga }
        func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] { [] }
    }
}
