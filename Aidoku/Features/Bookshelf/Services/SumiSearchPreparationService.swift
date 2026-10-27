#if SUMI
import AidokuRunner
import Foundation

/// Search publishes value snapshots after metadata and real chapter evidence
/// are ready. A row never starts another request merely because it is visible.
actor SumiSearchPreparationService {
    struct Details: Sendable {
        let manga: AidokuRunner.Manga
        let releaseYear: Int?
        let languages: SumiSearchLanguageInfo?
    }

    struct Outcome: Sendable {
        let books: [SumiBook]
        let failedSourceKeys: Set<String>
    }

    typealias Loader = @Sendable (SumiBook, AidokuRunner.Source?) async throws -> Details?
    static let shared = SumiSearchPreparationService()
    private let loader: Loader
    private let concurrency: Int
    private var cache: [Key: Entry] = [:]
    private var active: Set<Key> = []

    private struct Key: Hashable {
        let id: MangaIdentifier
        let source: ObjectIdentifier?
        let version: Int
        let preferences: Int
    }
    private struct Entry {
        let details: Details?
        let expires: Date
        let stored: Date
        var chapterCount: Int { details?.manga.chapters?.count ?? 0 }
    }
    private struct Prepared: Sendable {
        let index: Int
        let book: SumiBook?
        let failedSource: String?
    }

    init(concurrency: Int = 4, loader: Loader? = nil) {
        self.concurrency = max(1, concurrency)
        self.loader = loader ?? Self.load
    }

    func prepare(_ books: [SumiBook], sources: [String: AidokuRunner.Source] = [:]) async throws -> Outcome {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: Prepared.self) { group in
            var next = 0
            var ready: [Int: SumiBook] = [:]
            var failed: Set<String> = []
            for _ in 0..<min(concurrency, books.count) {
                let index = next
                next += 1
                group.addTask { await self.prepareOne(books[index], source: sources[books[index].sourceKey], index: index) }
            }
            while let result = try await group.next() {
                try Task.checkCancellation()
                if let book = result.book { ready[result.index] = book }
                if let source = result.failedSource { failed.insert(source) }
                if next < books.count {
                    let index = next
                    next += 1
                    group.addTask { await self.prepareOne(books[index], source: sources[books[index].sourceKey], index: index) }
                }
            }
            return Outcome(books: books.indices.compactMap { ready[$0] }, failedSourceKeys: failed)
        }
    }

    private func prepareOne(_ book: SumiBook, source: AidokuRunner.Source?, index: Int) async -> Prepared {
        let key = Key(id: book.id, source: source.map(ObjectIdentifier.init), version: source?.version ?? 0,
                      preferences: Self.preferencesFingerprint(sourceKey: book.sourceKey))
        do {
            while active.contains(key) || active.count >= concurrency {
                try await Task.sleep(for: .milliseconds(30))
                if let entry = cache[key], entry.expires > .now {
                    try Task.checkCancellation()
                    return Prepared(index: index, book: Self.apply(entry.details, to: book), failedSource: nil)
                }
            }
            try Task.checkCancellation()
            if let entry = cache[key], entry.expires > .now {
                return Prepared(index: index, book: Self.apply(entry.details, to: book), failedSource: nil)
            }
            active.insert(key)
            defer { active.remove(key) }
            let details = try await loader(book, source)
            try Task.checkCancellation()
            let now = Date.now
            cache = cache.filter { $0.value.expires > now }
            let chapterCount = details?.manga.chapters?.count ?? 0
            if chapterCount <= 12_000 {
                while cache.count >= 256 || cache.values.reduce(0, { $0 + $1.chapterCount }) + chapterCount > 12_000 {
                    guard let oldest = cache.min(by: { $0.value.stored < $1.value.stored })?.key else { break }
                    cache[oldest] = nil
                }
                cache[key] = Entry(details: details, expires: now.addingTimeInterval(details == nil ? 60 : 300), stored: now)
            }
            return Prepared(index: index, book: Self.apply(details, to: book), failedSource: nil)
        } catch is CancellationError {
            return Prepared(index: index, book: nil, failedSource: nil)
        } catch {
            // An unreachable source is unknown availability, never a zero count
            // and never a readable result. A later search can retry immediately.
            return Prepared(index: index, book: nil, failedSource: book.sourceKey)
        }
    }

    private static func apply(_ details: Details?, to book: SumiBook) -> SumiBook? {
        guard let details else { return nil }
        return book.updating(manga: SumiMangaMetadata.merging(book.manga, with: details.manga),
                             releaseYear: details.releaseYear, searchLanguages: details.languages)
    }

    private static func preferencesFingerprint(sourceKey: String) -> Int {
        let values = UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix(sourceKey + ".") }
        // Property-list encoding retains types and includes language/filter changes.
        let ordered: [[Any]] = values.keys.sorted().map { [$0, values[$0]!] }
        return (try? PropertyListSerialization.data(fromPropertyList: ordered, format: .binary, options: 0))?.hashValue ?? 0
    }

    private static func load(_ book: SumiBook, source: AidokuRunner.Source?) async throws -> Details? {
        try Task.checkCancellation()
        if let native = source?.runner as? HonbakoMangaDexRunner {
            let result = try await native.prepareSearchResult(book.manga)
            try Task.checkCancellation()
            guard result.manga.identifier == book.id else { throw URLError(.badServerResponse) }
            guard let chapter = result.readableChapter else { return nil }
            var manga = SumiMangaMetadata.merging(book.manga, with: result.manga)
            // One availability sample must never masquerade as a complete list.
            manga.chapters = book.manga.chapters
            return Details(manga: manga, releaseYear: book.releaseYear ?? result.releaseYear,
                languages: SumiSearchLanguageInfo(chapterLanguages: [chapter.language].compactMap { $0 },
                    translatedLanguages: result.translatedLanguages, sourceLanguages: []))
        }
        var manga = book.manga
        if manga.chapters?.isEmpty == true { return nil }
        if manga.chapters == nil || manga.authors?.isEmpty != false || manga.status == .unknown {
            guard let source else { throw URLError(.resourceUnavailable) }
            let fetched = try await source.getMangaUpdate(manga: manga, needsDetails: true, needsChapters: manga.chapters == nil)
            try Task.checkCancellation()
            guard fetched.identifier == book.id else { throw URLError(.badServerResponse) }
            manga = SumiMangaMetadata.merging(manga, with: fetched)
        }
        guard let chapters = manga.chapters else { throw URLError(.cannotParseResponse) }
        let readable = readableChapters(in: chapters, sourceAvailable: source != nil) { chapter in
            DownloadManager.shared.getDownloadStatus(for: .init(sourceKey: book.sourceKey,
                mangaKey: book.manga.key, chapterKey: chapter.key)) == .finished
        }
        guard !readable.isEmpty else { return nil }
        let metadata = await SumiSearchMetadataService.shared.metadata(for: book)
        try Task.checkCancellation()
        if manga.authors?.isEmpty != false, let authors = metadata?.authors, !authors.isEmpty { manga.authors = authors }
        if manga.status == .unknown, let status = metadata?.publishingStatus { manga.status = status }
        return Details(manga: manga, releaseYear: book.releaseYear ?? metadata?.releaseYear,
            languages: SumiSearchLanguageInfo(chapterLanguages: readable.compactMap(\.language),
                translatedLanguages: metadata?.translatedLanguages ?? [], sourceLanguages: source?.languages ?? []))
    }

    static func readableChapters(in chapters: [AidokuRunner.Chapter], sourceAvailable: Bool,
                                 isDownloaded: (AidokuRunner.Chapter) -> Bool) -> [AidokuRunner.Chapter] {
        chapters.filter { (sourceAvailable && !$0.locked) || isDownloaded($0) }
    }
}
#endif
