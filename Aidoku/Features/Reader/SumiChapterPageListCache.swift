#if SUMI
import AidokuRunner
import Foundation

/// A short-lived source-response cache. Bookmarks and decoded page images never
/// enter it; each reader still resolves its current language and progress.
actor SumiChapterPageListCache {
    struct Key: Hashable, Sendable {
        let sourceInstance: ObjectIdentifier
        let sourceKey: String
        let sourceVersion: Int
        let mangaKey: String
        let chapterKey: String
        let language: String

        init(source: AidokuRunner.Source, manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) {
            sourceInstance = ObjectIdentifier(source)
            sourceKey = source.key
            sourceVersion = source.version
            mangaKey = manga.key
            chapterKey = chapter.key
            language = SumiChapterLanguage.normalized(chapter.language ?? source.languages.first) ?? ""
        }

        init(sourceInstance: ObjectIdentifier, sourceKey: String, sourceVersion: Int = 1,
             mangaKey: String, chapterKey: String, language: String) {
            self.sourceInstance = sourceInstance
            self.sourceKey = sourceKey
            self.sourceVersion = sourceVersion
            self.mangaKey = mangaKey
            self.chapterKey = chapterKey
            self.language = language
        }
    }

    static let shared = SumiChapterPageListCache()
    private struct Entry {
        let pages: [AidokuRunner.Page]
        let source: AidokuRunner.Source?
        let expires: Date
        let stored: Date
        let cost: Int
    }
    private struct Flight {
        let id: UUID
        let started: Date
        let task: Task<[AidokuRunner.Page], Error>
    }
    private var entries: [Key: Entry] = [:]
    private var flights: [Key: Flight] = [:]
    private let lifetime: TimeInterval = 60
    private let maximumEntries = 8
    private let maximumCost = 4 * 1024 * 1024

    func pages(for key: Key, source: AidokuRunner.Source? = nil, forceRefresh: Bool = false,
               now: Date = .now,
               load: @escaping @Sendable () async throws -> [AidokuRunner.Page]) async throws -> [AidokuRunner.Page] {
        try Task.checkCancellation()
        entries = entries.filter { $0.value.expires > now }
        if forceRefresh { invalidate(key) }
        if let cached = entries[key] { return cached.pages }
        let flight: Flight
        if let active = flights[key] {
            flight = active
        } else {
            if flights.count >= maximumEntries,
               let oldest = flights.min(by: { $0.value.started < $1.value.started })?.key {
                flights.removeValue(forKey: oldest)?.task.cancel()
            }
            flight = Flight(id: UUID(), started: now, task: Task { try await load() })
            flights[key] = flight
        }
        do {
            let pages = try await flight.task.value
            if flights[key]?.id == flight.id {
                flights[key] = nil
                if let cost = Self.cost(of: pages) {
                    entries[key] = Entry(pages: pages, source: source, expires: now.addingTimeInterval(lifetime),
                                         stored: now, cost: cost)
                    while entries.count > maximumEntries || entries.values.reduce(0, { $0 + $1.cost }) > maximumCost {
                        guard let oldest = entries.min(by: { $0.value.stored < $1.value.stored })?.key else { break }
                        entries[oldest] = nil
                    }
                }
            }
            try Task.checkCancellation()
            return pages
        } catch {
            if flights[key]?.id == flight.id { flights[key] = nil }
            throw error
        }
    }

    func invalidate(_ key: Key) {
        entries[key] = nil
        flights.removeValue(forKey: key)?.task.cancel()
    }

    private static func cost(of pages: [AidokuRunner.Page]) -> Int? {
        guard !pages.isEmpty, pages.count <= 512 else { return nil }
        var cost = 0
        for page in pages {
            guard case let .url(url, context) = page.content,
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            cost += url.absoluteString.utf8.count + (page.thumbnail?.absoluteString.utf8.count ?? 0)
                + (page.description?.utf8.count ?? 0)
            for (key, value) in context ?? [:] { cost += key.utf8.count + value.utf8.count }
            guard cost <= 1024 * 1024 else { return nil }
        }
        return cost
    }
}
#endif
