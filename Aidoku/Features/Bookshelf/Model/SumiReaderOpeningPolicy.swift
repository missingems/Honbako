#if SUMI
import AidokuRunner

/// A copied history action, including completion. Presence of history, rather
/// than a guessed progress fraction, decides whether front matter is shown.
struct SumiReaderHistorySnapshot: Equatable, Sendable {
    let chapterKey: String
    let page: Int
    let completed: Bool

    var startPage: Int { completed ? 1 : max(1, page) }
}

enum SumiReaderOpeningPolicy {
    struct Choice: Equatable, Sendable {
        let chapterKey: String
        let startPage: Int
        let isFirstRead: Bool
    }

    static func eligibleChapters(history: SumiReaderHistorySnapshot?, chapters: [AidokuRunner.Chapter],
                                 preferredLanguage: String?) -> [AidokuRunner.Chapter] {
        if let history, let saved = chapters.first(where: { $0.key == history.chapterKey }) {
            if let language = SumiChapterLanguage.normalized(saved.language) {
                return SumiChapterLanguage.filter(chapters, language: language)
            }
            // Personal servers often omit language entirely. Keep an exact
            // unlabelled bookmark, rather than assigning it a guessed edition.
            return chapters.filter { SumiChapterLanguage.normalized($0.language) == nil }
        }
        guard !SumiChapterLanguage.languages(in: chapters).isEmpty else { return chapters }
        return SumiChapterLanguage.filter(chapters, language: preferredLanguage)
    }

    /// Canonical chapter order is newest-first. Try an exact bookmark first,
    /// then advance in reading order before considering earlier chapters.
    /// An automatic replacement starts at page one and is not marked read here.
    static func candidates(
        history: SumiReaderHistorySnapshot?,
        chaptersNewestFirst: [AidokuRunner.Chapter],
        canRead: (AidokuRunner.Chapter) -> Bool
    ) -> [Choice] {
        let chronological = Array(chaptersNewestFirst.reversed())
        let ordered: [AidokuRunner.Chapter]
        if let history, let index = chronological.firstIndex(where: { $0.key == history.chapterKey }) {
            ordered = [chronological[index]] + Array(chronological.dropFirst(index + 1))
                + Array(chronological.prefix(index).reversed())
        } else { ordered = chronological }
        var seen: Set<String> = []
        return ordered.filter { seen.insert($0.key).inserted && canRead($0) }.map { chapter in
            Choice(chapterKey: chapter.key,
                startPage: history.flatMap { $0.chapterKey == chapter.key ? $0.startPage : nil } ?? 1,
                isFirstRead: history == nil)
        }
    }

    static func choose(
        history: SumiReaderHistorySnapshot?,
        chaptersNewestFirst: [AidokuRunner.Chapter],
        canRead: (AidokuRunner.Chapter) -> Bool
    ) -> Choice? {
        candidates(history: history, chaptersNewestFirst: chaptersNewestFirst, canRead: canRead).first
    }
}
#endif
