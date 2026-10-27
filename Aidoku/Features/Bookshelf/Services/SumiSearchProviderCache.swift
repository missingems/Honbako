#if SUMI
import AidokuRunner
import Foundation

/// Reopening the same query should reuse the provider page as well as the
/// prepared rows. Source identity and settings remain part of that evidence.
actor SumiSearchProviderCache {
    typealias Loader = @Sendable (AidokuRunner.Source, String?) async throws -> [AidokuRunner.Manga]
    static let shared = SumiSearchProviderCache()

    private let loader: Loader
    private let maximumQueries: Int
    private let maximumMangaCount: Int
    private let lifetime: TimeInterval
    private let emptyLifetime: TimeInterval
    private var cache: [Key: Entry] = [:]
    private var active: Set<Key> = []

    private struct Key: Hashable {
        let sourceKey: String
        let source: ObjectIdentifier
        let version: Int
        let preferences: Int
        let query: String?
    }

    private struct Entry {
        // Hold the instance while its ObjectIdentifier is in the cache. A new
        // source cannot accidentally inherit an address reused after removal.
        let source: AidokuRunner.Source
        let manga: [AidokuRunner.Manga]
        let expires: Date
        let stored: Date
    }

    init(maximumQueries: Int = 64, maximumMangaCount: Int = 2_000,
         lifetime: TimeInterval = 60, emptyLifetime: TimeInterval = 30, loader: Loader? = nil) {
        self.maximumQueries = max(1, maximumQueries)
        self.maximumMangaCount = max(1, maximumMangaCount)
        self.lifetime = lifetime
        self.emptyLifetime = emptyLifetime
        self.loader = loader ?? Self.load
    }

    func entries(source: AidokuRunner.Source, query: String?) async throws -> [AidokuRunner.Manga] {
        try Task.checkCancellation()
        let key = Key(sourceKey: source.key, source: ObjectIdentifier(source), version: source.version,
                      preferences: SumiSearchSourcePreferences.fingerprint(sourceKey: source.key), query: query)
        while active.contains(key) {
            try await Task.sleep(for: .milliseconds(30))
            try Task.checkCancellation()
            if let entry = cache[key], entry.expires > .now { return entry.manga }
        }
        if let entry = cache[key], entry.expires > .now { return entry.manga }
        try Task.checkCancellation()
        active.insert(key)
        defer { active.remove(key) }
        let manga = try await loader(source, query)
        try Task.checkCancellation()
        let now = Date.now
        cache = cache.filter { $0.value.expires > now }
        if manga.count <= maximumMangaCount {
            while cache.count >= maximumQueries
                || cache.values.reduce(0, { $0 + $1.manga.count }) + manga.count > maximumMangaCount {
                guard let oldest = cache.min(by: { $0.value.stored < $1.value.stored })?.key else { break }
                cache[oldest] = nil
            }
            cache[key] = Entry(source: source, manga: manga,
                expires: now.addingTimeInterval(manga.isEmpty ? emptyLifetime : lifetime), stored: now)
        }
        return manga
    }

    private static func load(source: AidokuRunner.Source, query: String?) async throws -> [AidokuRunner.Manga] {
        if query == nil {
            let listings = try await source.getListings()
            if let listing = listings.first {
                return try await source.getMangaList(listing: listing, page: 1).entries
            }
        }
        return try await source.getSearchMangaList(query: query, page: 1, filters: []).entries
    }
}
#endif
