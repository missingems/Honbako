@testable import Sumi
import AidokuRunner
import Foundation
import Testing

struct HonbakoLibraryShelfTests {
    private func chapter(_ key: String, number: Double?, language: String = "en", locked: Bool = false,
                         uploaded: Date? = nil, completed: Date? = nil) -> SumiLibraryShelfSummary.Chapter {
        .init(key: key, number: number, volume: nil, language: language, scanlator: nil,
              locked: locked, uploaded: uploaded, completedAt: completed)
    }

    @Test("Finished requires reading every applicable chapter of a completed publication")
    func completionRequiresActualHistory() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let read = [chapter("one", number: 1, completed: date), chapter("two", number: 2, completed: date.addingTimeInterval(5))]
        #expect(SumiLibraryShelfSummary(status: .completed, chapters: read, language: "en").finishedAt == date.addingTimeInterval(5))
        #expect(SumiLibraryShelfSummary(status: .ongoing, chapters: read, language: "en").finishedAt == nil)
        #expect(SumiLibraryShelfSummary(status: .completed, chapters: [], language: "en").finishedAt == nil)
        let unfinished = read + [chapter("three", number: 3)]
        let summary = SumiLibraryShelfSummary(status: .completed, chapters: unfinished, language: "en")
        #expect(summary.finishedAt == nil && summary.unreadCount == 1)
    }

    @Test("Locked unread chapters prevent Finished without inflating available unread badges")
    func lockedChaptersRemainPartOfCompletion() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let read = chapter("one", number: 1, completed: date)
        let locked = chapter("two", number: 2, locked: true, uploaded: date.addingTimeInterval(5))
        let unfinished = SumiLibraryShelfSummary(status: .completed, chapters: [read, locked], language: "en")
        #expect(unfinished.finishedAt == nil)
        #expect(unfinished.unreadCount == 0)
        #expect(unfinished.latestUnreadDate == nil)

        let finishedDate = date.addingTimeInterval(10)
        let readLocked = chapter("two", number: 2, locked: true, completed: finishedDate)
        let finished = SumiLibraryShelfSummary(status: .completed, chapters: [read, readLocked], language: "en")
        #expect(finished.finishedAt == finishedDate)

        // Another edition of an already-read chapter is not another reading task.
        let duplicate = chapter("one-locked", number: 1, locked: true)
        let duplicates = SumiLibraryShelfSummary(status: .completed, chapters: [read, duplicate], language: "en")
        #expect(duplicates.finishedAt == date)
        #expect(duplicates.unreadCount == 0)
    }

    @Test("Unread badges respect translations, duplicate chapter editions, and locked chapters")
    func unreadCountsReadableEdition() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let chapters = [chapter("one-a", number: 1, completed: date), chapter("one-b", number: 1),
                        chapter("two-en", number: 2, uploaded: date), chapter("two-es", number: 2, language: "es"),
                        chapter("three", number: 3, locked: true)]
        let summary = SumiLibraryShelfSummary(status: .ongoing, chapters: chapters, language: "en")
        #expect(summary.unreadCount == 1)
        #expect(summary.latestUnreadDate == date)
        #expect(summary.finishedAt == nil)
    }

    @Test("Reading puts unread updates first and preserves collection order for equal urgency")
    func stableUnreadOrdering() {
        func book(_ key: String, unread: Int, uploaded: Date? = nil, finished: Date? = nil) -> SumiBook {
            SumiBook(manga: AidokuRunner.Manga(sourceKey: "test", key: key, title: key),
                     unreadChapterCount: unread, latestUnreadChapterDate: uploaded, finishedReadingAt: finished)
        }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let books = [book("a", unread: 0), book("b", unread: 2), book("c", unread: 2, uploaded: date),
                     book("d", unread: 0), book("finished", unread: 0, finished: date)]
        let sorted = SumiLibraryShelfSummary.readingOrder(books, stableIDs: ["test:d", "test:a", "test:b", "test:c", "test:finished"])
        #expect(sorted.map(\.manga.key) == ["c", "b", "d", "a"])
    }
}
