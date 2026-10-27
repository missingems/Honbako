@testable import Sumi
import AidokuRunner
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct HonbakoPopularStoreTests {
    @Test("No added sources means no Popular books, including old cached providers")
    func emptyConnectionsNeverExposeCachedProviders() async throws {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cache = HonbakoPopularCache(url: url)
        let identity = HonbakoPopularConnection.Identity(sourceKey: "removed", revision: "1")
        try await cache.save([.init(identity: identity, date: .now, entries: manga(source: "removed", count: 2))], generation: 0)
        let store = HonbakoPopularStore(cacheURL: url, observesSourceChanges: false, coverPreparer: { _ in }, connectionLoader: { [] })
        await store.refresh()
        #expect(!store.hasSources)
        #expect(store.books.isEmpty)
        #expect(!store.isLoading)
        #expect(try await cache.load().isEmpty)
    }

    @Test("Source rankings interleave and matching titles are not repeated across providers")
    func aggregateRankings() {
        let first = manga(source: "one", count: 3)
        var second = manga(source: "two", count: 3)
        second[1].title = first[0].title
        let books = HonbakoPopularAggregation.books(catalogs: [first, second], previouslyPublished: [])
        #expect(books.map(\.manga.key) == ["one-0", "two-0", "one-1", "one-2", "two-2"])
        #expect(books.first?.sourceKey == "one")
        #expect(books.first?.coverURL?.absoluteString == "https://example.com/one-0.jpg")
    }

    @Test("Popular snapshots retain source artwork and omit chapter payloads and invalid entries")
    func validateCatalogEntries() {
        var entry = manga(source: "source", count: 1)[0]
        entry.chapters = [.init(key: "not-a-popularity-cache")]
        let missingCover = AidokuRunner.Manga(sourceKey: "source", key: "missing", title: "No Cover")
        let foreign = manga(source: "foreign", count: 1)[0]
        var adult = entry
        adult.contentRating = .nsfw
        let accepted = HonbakoPopularAggregation.candidates([entry, entry, missingCover, foreign, adult], sourceKey: "source")
        #expect(accepted.count == 1)
        #expect(accepted.first?.identifier == entry.identifier)
        #expect(accepted.first?.cover == entry.cover)
        #expect(accepted.first?.chapters == nil)
    }

    @Test("Warm catalog refreshes coalesce and only the current connection revision is reused")
    func cacheAndRevisionInvalidation() async throws {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let calls = Calls()
        let entries = manga(source: "source", count: 2)
        let connections = Connections()
        connections.values = [.init(key: "source", load: { await calls.record(); return entries })]
        let store = HonbakoPopularStore(cacheURL: url, observesSourceChanges: false, coverPreparer: { _ in }, connectionLoader: { connections.values })
        async let first: Void = store.refresh()
        async let second: Void = store.refresh()
        _ = await (first, second)
        await store.refresh()
        #expect(await calls.count == 1)
        #expect(store.books.map(\.id) == entries.map(\.identifier))
        let revisedCatalog = SuspendedCatalog()
        connections.values = [.init(key: "source", revision: "new-language-or-version", load: {
            await calls.record()
            return await revisedCatalog.load()
        })]
        let revisionRefresh = Task { await store.refresh() }
        for _ in 0..<100 {
            if await revisedCatalog.started { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await revisedCatalog.started)
        #expect(store.books.isEmpty, "A new source revision must not show the stale previous metadata")
        await revisedCatalog.finish(Array(entries.reversed()))
        await revisionRefresh.value
        #expect(await calls.count == 2)
        #expect(store.books.map(\.id) == entries.map(\.identifier), "Refreshing metadata must preserve visible cover slots")
        #expect(!store.isLoading)
    }

    @Test("A matching on-disk source cache renders immediately without fetching again")
    func diskCacheIsScopedToEnabledConnection() async throws {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let entries = manga(source: "enabled", count: 2)
        let first = HonbakoPopularStore(cacheURL: url, observesSourceChanges: false, coverPreparer: { _ in }, connectionLoader: {
            [.init(key: "enabled", load: { entries })]
        })
        await first.refresh()
        let second = HonbakoPopularStore(cacheURL: url, observesSourceChanges: false, coverPreparer: { _ in }, connectionLoader: {
            [.init(key: "enabled", load: {
                Issue.record("A matching fresh popularity cache must not access the provider")
                return []
            })]
        })
        await second.refresh()
        #expect(second.hasSources)
        #expect(second.books.map(\.id) == entries.map(\.identifier))
        #expect(second.books.map(\.coverURL) == entries.map { $0.cover.flatMap(URL.init(string:)) })
    }

    @Test("A Popular source's covers are prepared before its complete grid batch is published")
    func coverPreparationPrecedesPublication() async throws {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let entries = manga(source: "source", count: 4)
        let gate = SuspendedCatalog()
        let store = HonbakoPopularStore(cacheURL: url, observesSourceChanges: false,
            coverPreparer: { books in if !books.isEmpty { _ = await gate.load() } },
            connectionLoader: { [.init(key: "source", load: { entries })] })
        let task = Task { await store.refresh() }
        defer { task.cancel(); Task { await gate.finish([]) } }
        for _ in 0..<100 {
            if await gate.started { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await gate.started)
        #expect(store.books.isEmpty)
        #expect(store.isLoading)
        await gate.finish([])
        await task.value
        #expect(store.books.map(\.id) == entries.map(\.identifier))
    }

    @Test("Returning to a fresh Popular catalog retries cover preparation without refetching metadata or reordering books")
    func freshCatalogRetriesCoverPreparation() async throws {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let entries = manga(source: "source", count: 4)
        let catalogCalls = Calls()
        let coverCalls = Calls()
        let store = HonbakoPopularStore(cacheURL: url, observesSourceChanges: false,
            coverPreparer: { books in if !books.isEmpty { await coverCalls.record() } },
            connectionLoader: { [.init(key: "source", load: { await catalogCalls.record(); return entries })] })
        await store.refresh()
        let original = store.books.map(\.id)
        #expect(await coverCalls.count == 1)
        await store.refresh()
        #expect(await coverCalls.count == 2)
        #expect(await catalogCalls.count == 1)
        #expect(store.books.map(\.id) == original)
    }

    @Test("Opening search cancels cover warming for a fresh cached Popular catalog")
    func pauseCancelsCachedCoverWarming() async throws {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let entries = manga(source: "source", count: 4)
        let covers = CoverAttempts()
        let store = HonbakoPopularStore(cacheURL: url, observesSourceChanges: false,
            coverPreparer: { await covers.prepare($0) },
            connectionLoader: { [.init(key: "source", load: { entries })] })
        await store.refresh()
        let original = store.books.map(\.id)
        await covers.arm()
        let refresh = Task { await store.refresh() }
        defer { refresh.cancel() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await covers.started), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(await covers.started)
        store.setPaused(true)
        await refresh.value
        #expect(await covers.cancelled)
        #expect(store.books.map(\.id) == original)
        #expect(store.failures.isEmpty)
        #expect(!store.isLoading)
    }

    @Test("A working provider publishes before a slow provider and errors do not remove its covers")
    func publishWorkingSourceIndependently() async throws {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let entries = manga(source: "fast", count: 2)
        let gate = SuspendedCatalog()
        let store = HonbakoPopularStore(cacheURL: url, observesSourceChanges: false, coverPreparer: { _ in }, connectionLoader: {
            [.init(key: "fast", load: { entries }),
             .init(key: "slow", load: { await gate.load() }),
             .init(key: "broken", load: { throw URLError(.cannotConnectToHost) })]
        })
        let task = Task { await store.refresh() }
        for _ in 0..<100 where store.books.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(store.books.map(\.id) == entries.map(\.identifier))
        #expect(store.isLoading)
        let slow = manga(source: "slow", count: 2)
        await gate.finish(slow)
        await task.value
        #expect(store.books.prefix(2).map(\.id) == entries.map(\.identifier))
        #expect(store.books.count == 4)
        #expect(store.failures == ["broken"])
        #expect(!store.isLoading)
    }

    @Test("Removing a source discards its late noncancellable catalog response")
    func removalDiscardsLateResponse() async throws {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let gate = SuspendedCatalog()
        let connections = Connections()
        connections.values = [.init(key: "removed", load: { await gate.load() })]
        let store = HonbakoPopularStore(cacheURL: url, observesSourceChanges: false, coverPreparer: { _ in }, connectionLoader: { connections.values })
        let pending = Task { await store.refresh() }
        for _ in 0..<100 {
            if await gate.started { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await gate.started)
        connections.values = []
        await store.refresh()
        await gate.finish(manga(source: "removed", count: 2))
        await pending.value
        #expect(!store.hasSources)
        #expect(store.books.isEmpty)
        #expect(!store.isLoading)
        #expect(try await HonbakoPopularCache(url: url).load().isEmpty)
    }

    @Test("Only provider-labelled popularity or explicit ranking sections are used")
    func explicitPopularitySelection() {
        let latest = AidokuRunner.Listing(id: "latest", name: "Latest Updates")
        let popular = AidokuRunner.Listing(id: "popular", name: "Popular")
        #expect(HonbakoPopularLoader.popularListing(in: [latest, popular]) == popular)
        #expect(HonbakoPopularLoader.popularListing(in: [latest]) == nil)
        let entry = manga(source: "source", count: 1)[0]
        let link = AidokuRunner.HomeComponent.Value.Link(title: entry.title, imageUrl: entry.cover, value: .manga(entry))
        let home = AidokuRunner.Home(components: [
            .init(title: "Latest", value: .scroller(entries: [link])),
            .init(title: nil, value: .mangaList(ranking: true, entries: [link]))
        ])
        #expect(HonbakoPopularLoader.popularManga(in: home).map(\.identifier) == [entry.identifier])
        #expect(HonbakoPopularLoader.isPopularLabel("熱門漫畫"))
        #expect(HonbakoPopularLoader.isPopularLabel("ランキング"))
        let keyOnly = AidokuRunner.Manga(sourceKey: "source", key: "key-only", title: "")
        let preview = AidokuRunner.HomeComponent.Value.Link(title: "Provided Link Title",
            imageUrl: "https://example.com/link-cover.jpg", value: .manga(keyOnly))
        let linked = HonbakoPopularLoader.popularManga(in: .init(components: [
            .init(title: "Popular", value: .scroller(entries: [preview]))
        ]))
        #expect(linked.first?.title == "Provided Link Title")
        #expect(linked.first?.cover == preview.imageUrl)
    }

    @Test("Search pauses background popularity work and discards its late response")
    func searchHasPriority() async throws {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let gate = SuspendedCatalog()
        let calls = Calls()
        let entries = manga(source: "source", count: 2)
        let store = HonbakoPopularStore(cacheURL: url, observesSourceChanges: false, coverPreparer: { _ in }, connectionLoader: {
            [.init(key: "source", load: {
                await calls.record()
                return await gate.load()
            })]
        })
        let pending = Task { await store.refresh() }
        for _ in 0..<100 {
            if await gate.started { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        store.setPaused(true)
        await store.refresh()
        #expect(await calls.count == 1)
        await gate.finish(entries)
        await pending.value
        #expect(store.books.isEmpty)
        #expect(!store.isLoading)
    }

    nonisolated private func manga(source: String, count: Int) -> [AidokuRunner.Manga] {
        (0..<count).map { index in
            AidokuRunner.Manga(sourceKey: source, key: "\(source)-\(index)", title: "\(source) Manga \(index)",
                cover: "https://example.com/\(source)-\(index).jpg", authors: ["Fixture Author"])
        }
    }

    private func temporaryCacheURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "HonbakoPopularTests-\(UUID())", directoryHint: .isDirectory)
            .appending(path: "popular.json")
    }

    @MainActor private final class Connections { var values: [HonbakoPopularConnection] = [] }
    private actor Calls {
        var count = 0
        func record() { count += 1 }
    }
    private actor CoverAttempts {
        private var armed = false
        var started = false
        var cancelled = false
        func arm() { armed = true }
        func prepare(_ books: [SumiBook]) async {
            guard armed, !books.isEmpty else { return }
            started = true
            do { try await Task.sleep(for: .seconds(30)) }
            catch is CancellationError { cancelled = true }
            catch { }
        }
    }
    private actor SuspendedCatalog {
        var started = false
        private var continuation: CheckedContinuation<[AidokuRunner.Manga], Never>?
        private var queued: [AidokuRunner.Manga]?
        func load() async -> [AidokuRunner.Manga] {
            if let queued { return queued }
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                started = true
            }
        }
        func finish(_ manga: [AidokuRunner.Manga]) {
            if let continuation { continuation.resume(returning: manga) }
            else { queued = manga }
            continuation = nil
        }
    }
}
