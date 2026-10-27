#if SUMI
import Foundation

/// Positions belong to the collection, independent of the latest reading history.
/// Retain unavailable IDs too, so a temporarily missing source does not move a book.
@MainActor
struct SumiGridOrder {
    private(set) var identifiers: [String]
    private let defaults: UserDefaults?
    private let key: String

    init(defaults: UserDefaults? = .standard, key: String = "Sumi.Grid.Order.v1") {
        self.defaults = defaults
        self.key = key
        var seen: Set<String> = []
        identifiers = (defaults?.stringArray(forKey: key) ?? []).filter { seen.insert($0).inserted }
    }

    mutating func books(catalog: [SumiBook], library: [SumiBook]) -> [SumiBook] {
        // New saved titles append in canonical order rather than the store's
        // last-opened order, preserving the reader's existing arrangement.
        let candidates = catalog + library.sorted { $0.presentation.id < $1.presentation.id }
        var seen = Set(identifiers)
        let additions = candidates.map { $0.presentation.id }.filter { seen.insert($0).inserted }
        if !additions.isEmpty {
            identifiers.append(contentsOf: additions)
            defaults?.set(identifiers, forKey: key)
        }

        var available: [String: SumiBook] = [:]
        for book in candidates where available[book.presentation.id] == nil {
            available[book.presentation.id] = book
        }
        let progress = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return identifiers.compactMap { identifier in
            guard let book = available[identifier] else { return nil }
            guard let saved = progress[book.id] else { return book }
            return SumiBook(manga: book.manga, chapterLabel: saved.chapterLabel,
                            pageLabel: saved.pageLabel, progress: saved.progress,
                            isInLibrary: true, lastRead: saved.lastRead, bookmark: saved.bookmark,
                            resumeDeviceLabel: saved.resumeDeviceLabel, lastReadPage: saved.lastReadPage,
                            releaseDate: saved.releaseDate, releaseYear: saved.releaseYear,
                            unreadChapterCount: saved.unreadChapterCount,
                            latestUnreadChapterDate: saved.latestUnreadChapterDate, finishedReadingAt: saved.finishedReadingAt)
        }
    }
}
#endif
