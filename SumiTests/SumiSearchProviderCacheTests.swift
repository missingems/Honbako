@testable import Sumi
import AidokuRunner
import Foundation
import Testing

struct SumiSearchProviderCacheTests {
    @Test("Repeated provider queries reuse raw pages and concurrent requests share the same result")
    func cachedAndConcurrentQueries() async throws {
        let probe = Probe(delay: .milliseconds(30))
        let cache = SumiSearchProviderCache(loader: { try await probe.load(source: $0, query: $1) })
        let source = source()
        async let first = cache.entries(source: source, query: "One Piece")
        async let duplicate = cache.entries(source: source, query: "One Piece")
        let pages = try await [first, duplicate]
        #expect(pages.allSatisfy { $0.first?.title == "One Piece" })
        #expect(await probe.count == 1)
        let cached = try await cache.entries(source: source, query: "One Piece")
        #expect(cached.first?.sourceKey == source.key)
        #expect(await probe.count == 1)
    }

    @Test("Catalog, empty text, and typed queries have separate cache entries")
    func distinctQueryKinds() async throws {
        let probe = Probe()
        let cache = SumiSearchProviderCache(loader: { try await probe.load(source: $0, query: $1) })
        let source = source()
        for query in [nil, "", "Title", nil, "", "Title"] as [String?] {
            _ = try await cache.entries(source: source, query: query)
        }
        #expect(await probe.count == 3)
    }

    @Test("Replacing a source instance, upgrading it, or changing language cannot reuse stale provider pages")
    func sourceAndPreferenceInvalidation() async throws {
        let probe = Probe()
        let cache = SumiSearchProviderCache(loader: { try await probe.load(source: $0, query: $1) })
        let key = "cache-fixture-\(UUID().uuidString)"
        let preference = key + ".languages"
        defer { UserDefaults.standard.removeObject(forKey: preference) }
        let original = source(key: key)
        UserDefaults.standard.set(["en"], forKey: preference)
        _ = try await cache.entries(source: original, query: "Title")
        _ = try await cache.entries(source: original, query: "Title")
        #expect(await probe.count == 1)
        UserDefaults.standard.set(["fr"], forKey: preference)
        _ = try await cache.entries(source: original, query: "Title")
        #expect(await probe.count == 2)
        let replaced = source(key: key)
        _ = try await cache.entries(source: replaced, query: "Title")
        #expect(await probe.count == 3)
        let upgraded = source(key: key, version: 2)
        _ = try await cache.entries(source: upgraded, query: "Title")
        #expect(await probe.count == 4)
    }

    @Test("Unknown availability from failed or cancelled provider requests is never cached")
    func failureAndCancellationStayRetryable() async throws {
        let failing = Probe(failFirst: true)
        let cache = SumiSearchProviderCache(loader: { try await failing.load(source: $0, query: $1) })
        let source = source()
        do {
            _ = try await cache.entries(source: source, query: "Title")
            Issue.record("The fixture's first provider request should fail")
        } catch { #expect(error is URLError) }
        #expect(try await cache.entries(source: source, query: "Title").count == 1)
        #expect(await failing.count == 2)

        let slow = Probe(delay: .milliseconds(100))
        let cancelCache = SumiSearchProviderCache(loader: { try await slow.load(source: $0, query: $1) })
        let task = Task { try await cancelCache.entries(source: source, query: "Title") }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await slow.count == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(await slow.count == 1)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("A cancelled provider request must not publish a page")
        } catch is CancellationError { }
        #expect(try await cancelCache.entries(source: source, query: "Title").count == 1)
        #expect(await slow.count == 2)
    }

    @Test("Cache budgets evict old queries and avoid retaining oversized provider pages")
    func boundedRetention() async throws {
        let probe = Probe()
        let source = source()
        let queries = SumiSearchProviderCache(maximumQueries: 2,
            loader: { try await probe.load(source: $0, query: $1) })
        for query in ["First", "Second", "Third", "First"] {
            _ = try await queries.entries(source: source, query: query)
        }
        #expect(await probe.count == 4)

        let crowded = Probe(pageSize: 2)
        let manga = SumiSearchProviderCache(maximumMangaCount: 3,
            loader: { try await crowded.load(source: $0, query: $1) })
        for query in ["First", "Second", "First"] {
            _ = try await manga.entries(source: source, query: query)
        }
        #expect(await crowded.count == 3)
        let oversized = Probe(pageSize: 4)
        let bounded = SumiSearchProviderCache(maximumMangaCount: 3,
            loader: { try await oversized.load(source: $0, query: $1) })
        #expect(try await bounded.entries(source: source, query: "Title").count == 4)
        #expect(try await bounded.entries(source: source, query: "Title").count == 4)
        #expect(await oversized.count == 2)
    }

    @Test("Known empty pages use their own short-lived negative cache")
    func emptyPageLifetime() async throws {
        let empty = Probe(pageSize: 0)
        let cache = SumiSearchProviderCache(lifetime: 0, emptyLifetime: 30,
            loader: { try await empty.load(source: $0, query: $1) })
        let source = source()
        #expect(try await cache.entries(source: source, query: "Missing").isEmpty)
        #expect(try await cache.entries(source: source, query: "Missing").isEmpty)
        #expect(await empty.count == 1)
        let expired = SumiSearchProviderCache(emptyLifetime: 0,
            loader: { try await empty.load(source: $0, query: $1) })
        _ = try await expired.entries(source: source, query: "Missing")
        _ = try await expired.entries(source: source, query: "Missing")
        #expect(await empty.count == 3)
    }

    @Test("Default catalog fetching uses the first listing while text search uses the source search endpoint")
    func defaultProviderRouting() async throws {
        let key = "routing-fixture-\(UUID().uuidString)"
        let runner = FixtureRunner(sourceKey: key)
        let source = AidokuRunner.Source(key: key, name: "Fixture", version: 1,
            contentRating: .safe, staticListings: [.init(id: "popular", name: "Popular")], runner: runner)
        let cache = SumiSearchProviderCache()
        #expect(try await cache.entries(source: source, query: nil).first?.title == "Listing")
        #expect(try await cache.entries(source: source, query: "Title").first?.title == "Search")
        #expect(await runner.routes == ["listing:popular:1", "search:Title:1"])
    }

    private func source(key: String = "cache-fixture-\(UUID().uuidString)", version: Int = 1) -> AidokuRunner.Source {
        .init(key: key, name: "Fixture", version: version, contentRating: .safe,
              runner: FixtureRunner(sourceKey: key))
    }

    private actor Probe {
        private(set) var count = 0
        let delay: Duration
        let pageSize: Int
        let failFirst: Bool
        init(delay: Duration = .zero, pageSize: Int = 1, failFirst: Bool = false) {
            self.delay = delay; self.pageSize = pageSize; self.failFirst = failFirst
        }
        func load(source: AidokuRunner.Source, query: String?) async throws -> [AidokuRunner.Manga] {
            count += 1
            if failFirst, count == 1 { throw URLError(.timedOut) }
            if delay > .zero { try await Task.sleep(for: delay) }
            return (0..<pageSize).map {
                .init(sourceKey: source.key, key: "\(query ?? "catalog")-\($0)", title: query ?? "Catalog")
            }
        }
    }

    private actor FixtureRunner: AidokuRunner.Runner {
        nonisolated let features = AidokuRunner.SourceFeatures(providesListings: true)
        let sourceKey: String
        private(set) var routes: [String] = []
        init(sourceKey: String) { self.sourceKey = sourceKey }
        func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
            routes.append("search:\(query ?? "nil"):\(page)")
            return .init(entries: [.init(sourceKey: sourceKey, key: "search", title: "Search")], hasNextPage: false)
        }
        func getMangaList(listing: AidokuRunner.Listing, page: Int) async throws -> AidokuRunner.MangaPageResult {
            routes.append("listing:\(listing.id):\(page)")
            return .init(entries: [.init(sourceKey: sourceKey, key: "listing", title: "Listing")], hasNextPage: false)
        }
        func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga { manga }
        func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] { [] }
    }
}
