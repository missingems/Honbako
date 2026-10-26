#if SUMI
import AidokuRunner
import Foundation

struct SumiLibraryShelfSummary: Equatable, Sendable {
    struct Chapter: Sendable {
        let key: String
        let number: Double?
        let volume: Double?
        let language: String
        let scanlator: String?
        let locked: Bool
        let uploaded: Date?
        let completedAt: Date?
    }

    let unreadCount: Int
    let latestUnreadDate: Date?
    let finishedAt: Date?

    init(status: AidokuRunner.PublishingStatus, chapters: [Chapter], language: String?, scanlators: [String]? = nil) {
        let selectedLanguage = language.flatMap { $0.isEmpty ? nil : $0 }
        let selectedScanlators = scanlators.flatMap { $0.isEmpty ? nil : Set($0) }
        let eligible = chapters.filter {
            (selectedLanguage == nil || $0.language == selectedLanguage)
                && (selectedScanlators == nil || selectedScanlators?.contains($0.scanlator ?? "") == true)
        }
        // Different translations are separate editions. With no stored choice,
        // use one language rather than counting the same chapter in every language.
        let effectiveLanguage = selectedLanguage ?? Dictionary(grouping: eligible, by: \.language)
            .max { lhs, rhs in lhs.value.count == rhs.value.count ? lhs.key > rhs.key : lhs.value.count < rhs.value.count }?.key
        let selected = eligible.filter { effectiveLanguage == nil || $0.language == effectiveLanguage }
        let groups = Dictionary(grouping: selected) { chapter in
            chapter.number.map { "\(chapter.volume ?? 0):\($0)" } ?? "key:\(chapter.key)"
        }
        // Locked chapters still belong to the publication. They prevent Finished
        // until read, but only currently readable chapters contribute to badges.
        let unread = groups.values.filter { !$0.contains { ($0.completedAt ?? .distantPast) > .distantPast } }
        let availableUnread = unread.filter { $0.contains { !$0.locked } }
        unreadCount = availableUnread.count
        latestUnreadDate = availableUnread.flatMap { $0.filter { !$0.locked }.compactMap(\.uploaded) }.max()
        let dates = groups.values.compactMap { $0.compactMap(\.completedAt).filter { $0 > .distantPast }.max() }
        finishedAt = status == .completed && !groups.isEmpty && unread.isEmpty && dates.count == groups.count
            ? dates.max() : nil
    }

    static func readingOrder(_ books: [SumiBook], stableIDs: [String]) -> [SumiBook] {
        let positions = Dictionary(stableIDs.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return books.filter { $0.finishedReadingAt == nil }.sorted {
            if $0.unreadChapterCount != $1.unreadChapterCount { return $0.unreadChapterCount > $1.unreadChapterCount }
            let lhsDate = $0.latestUnreadChapterDate ?? .distantPast
            let rhsDate = $1.latestUnreadChapterDate ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            let leftID = "\($0.sourceKey):\($0.manga.key)"
            let rightID = "\($1.sourceKey):\($1.manga.key)"
            let left = positions[leftID] ?? .max
            let right = positions[rightID] ?? .max
            return left == right ? leftID < rightID : left < right
        }
    }
}
#endif
