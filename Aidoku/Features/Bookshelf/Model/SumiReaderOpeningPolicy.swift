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
    struct Choice: Equatable {
        let chapterKey: String
        let startPage: Int
        let isFirstRead: Bool
    }

    /// The canonical reader uses newest-first chapter order. An existing
    /// history action always selects its exact chapter or reports unavailable.
    static func choose(
        history: SumiReaderHistorySnapshot?,
        chaptersNewestFirst: [AidokuRunner.Chapter],
        canRead: (AidokuRunner.Chapter) -> Bool
    ) -> Choice? {
        if let history {
            guard let chapter = chaptersNewestFirst.first(where: { $0.key == history.chapterKey }),
                  canRead(chapter) else { return nil }
            return Choice(chapterKey: chapter.key, startPage: history.startPage, isFirstRead: false)
        }
        guard let chapter = chaptersNewestFirst.reversed().first(where: canRead) else { return nil }
        return Choice(chapterKey: chapter.key, startPage: 1, isFirstRead: true)
    }
}
#endif
