@testable import Sumi
import AidokuRunner
import Testing

@Suite struct SumiReaderOpeningPolicyTests {
    private let chapters = ["chapter-3", "chapter-2", "chapter-1"].map { AidokuRunner.Chapter(key: $0) }

    @Test("A completed latest chapter reopens that chapter at page one, never the next chapter")
    func completedHistory() {
        let history = SumiReaderHistorySnapshot(chapterKey: "chapter-2", page: 24, completed: true)
        let choice = SumiReaderOpeningPolicy.choose(history: history, chaptersNewestFirst: chapters, canRead: { _ in true })
        #expect(choice == .init(chapterKey: "chapter-2", startPage: 1, isFirstRead: false))
    }

    @Test("Positive saved progress resumes its exact chapter without a guessed total")
    func unfinishedHistory() {
        let history = SumiReaderHistorySnapshot(chapterKey: "chapter-1", page: 7, completed: false)
        let choice = SumiReaderOpeningPolicy.choose(history: history, chaptersNewestFirst: chapters, canRead: { _ in true })
        #expect(choice == .init(chapterKey: "chapter-1", startPage: 7, isFirstRead: false))
    }

    @Test("A missing or unavailable last-read chapter cannot silently fall back")
    func unavailableHistory() {
        let missing = SumiReaderHistorySnapshot(chapterKey: "removed", page: 7, completed: false)
        #expect(SumiReaderOpeningPolicy.choose(history: missing, chaptersNewestFirst: chapters, canRead: { _ in true }) == nil)
        let locked = SumiReaderHistorySnapshot(chapterKey: "chapter-2", page: 7, completed: false)
        #expect(SumiReaderOpeningPolicy.choose(history: locked, chaptersNewestFirst: chapters,
                                               canRead: { $0.key != "chapter-2" }) == nil)
    }

    @Test("Only absent history creates first-read front matter at the oldest readable chapter")
    func firstRead() {
        let choice = SumiReaderOpeningPolicy.choose(history: nil, chaptersNewestFirst: chapters,
                                                    canRead: { $0.key != "chapter-1" })
        #expect(choice == .init(chapterKey: "chapter-2", startPage: 1, isFirstRead: true))
        let zero = SumiReaderHistorySnapshot(chapterKey: "chapter-1", page: 0, completed: false)
        #expect(SumiReaderOpeningPolicy.choose(history: zero, chaptersNewestFirst: chapters, canRead: { _ in true })
            == .init(chapterKey: "chapter-1", startPage: 1, isFirstRead: false))
    }
}
