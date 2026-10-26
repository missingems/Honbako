#if SUMI
import AidokuRunner
import Foundation

/// A search row represents a title, while keeping each provider's edition
/// selectable. Matching deliberately avoids fuzzy aliases and sequel names.
enum SumiSearchRanking {
    struct Group {
        var editions: [SumiBook]
        var book: SumiBook { editions[0] }
    }

    static func groups(_ books: [SumiBook], query: String) -> [Group] {
        var seen: Set<MangaIdentifier> = []
        let sorted = books.filter { seen.insert($0.id).inserted }.sorted { precedes($0, $1, query: query) }
        var groups: [Group] = []
        for book in sorted {
            let title = normalized(book.title)
            let authors = Set((book.manga.authors ?? []).map(normalized).filter { !$0.isEmpty })
            let match = groups.firstIndex { group in
                guard title.count >= 3, normalized(group.book.title) == title,
                      !group.editions.contains(where: { $0.sourceKey == book.sourceKey }) else { return false }
                // Do not collapse unrelated works that happen to share a name.
                return group.editions.allSatisfy { edition in
                    let known = Set((edition.manga.authors ?? []).map(normalized).filter { !$0.isEmpty })
                    return authors.isEmpty || known.isEmpty || !known.isDisjoint(with: authors)
                }
            }
            if let match { groups[match].editions.append(book) }
            else { groups.append(Group(editions: [book])) }
        }
        return groups
    }

    static func normalized(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let words = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined()
        return words.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func precedes(_ lhs: SumiBook, _ rhs: SumiBook, query: String) -> Bool {
        let query = normalized(query)
        func match(_ book: SumiBook) -> Int {
            let title = normalized(book.title)
            return query.isEmpty || title == query ? 0 : title.hasPrefix(query) ? 1 : title.contains(query) ? 2 : 3
        }
        if match(lhs) != match(rhs) { return match(lhs) < match(rhs) }
        if lhs.isInLibrary != rhs.isInLibrary { return lhs.isInLibrary }
        if lhs.hasUnfinishedBookmark != rhs.hasUnfinishedBookmark { return lhs.hasUnfinishedBookmark }
        let lhsLocal = lhs.sourceKey == LocalSourceRunner.sourceKey
        let rhsLocal = rhs.sourceKey == LocalSourceRunner.sourceKey
        if lhsLocal != rhsLocal { return lhsLocal }
        func availability(_ book: SumiBook) -> Int {
            guard let chapters = book.manga.chapters, !chapters.isEmpty else { return 1 }
            return chapters.contains(where: { !$0.locked }) ? 0 : 2
        }
        if availability(lhs) != availability(rhs) { return availability(lhs) < availability(rhs) }
        // Prefer a publisher's edition when both are otherwise equally useful.
        let lhsPublisher = lhs.sourceKey == "multi.mangaplus"
        let rhsPublisher = rhs.sourceKey == "multi.mangaplus"
        if lhsPublisher != rhsPublisher { return lhsPublisher }
        let titleOrder = normalized(lhs.title).compare(normalized(rhs.title))
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        if lhs.sourceKey != rhs.sourceKey { return lhs.sourceKey < rhs.sourceKey }
        return lhs.manga.key < rhs.manga.key
    }
}
#endif
