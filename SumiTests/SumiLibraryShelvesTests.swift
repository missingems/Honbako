@testable import Sumi
import AidokuRunner
import Foundation
import Testing

struct SumiLibraryShelvesTests {
    @Test("A shelf snapshot keeps finished books visible and separates them from Reading")
    func finishedBooksRemainAvailable() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let reading = book("reading")
        let older = book("older", finished: date)
        let newer = book("newer", finished: date.addingTimeInterval(60))
        let shelves = SumiLibraryShelves(books: [older, reading, newer])
        #expect(shelves.reading.map(\.id) == [reading.id])
        #expect(shelves.finished.map(\.id) == [newer.id, older.id])
        #expect(shelves.visibleCount(hideFinished: false) == 3)
        #expect(shelves.visibleCount(hideFinished: true) == 1)
        #expect(shelves.finished.map(\.finishedReadingAt) == [date.addingTimeInterval(60), date])
    }

    @Test("A completely finished collection is still a nonempty library by default")
    func allFinishedStillVisible() {
        let shelves = SumiLibraryShelves(books: [book("finished", finished: .now)])
        #expect(shelves.reading.isEmpty)
        #expect(shelves.visibleCount(hideFinished: false) == 1)
        #expect(shelves.visibleCount(hideFinished: true) == 0)
        #expect(shelves.finished.count == 1)
    }

    @Test("Cached shelves preserve tutorial priority, unread order, and stable collection positions")
    func readingSnapshotPreservesOrdering() {
        let tutorial = book("tutorial")
        let quiet = book("quiet")
        let urgent = book("urgent", unread: 3)
        let shelves = SumiLibraryShelves(books: [quiet, urgent, tutorial],
            stableIDs: ["shelf:quiet", "shelf:urgent", "shelf:tutorial"], tutorialIdentifier: tutorial.id)
        #expect(shelves.reading.map(\.id) == [tutorial.id, urgent.id, quiet.id])
    }

    private func book(_ key: String, finished: Date? = nil, unread: Int = 0) -> SumiBook {
        SumiBook(manga: AidokuRunner.Manga(sourceKey: "shelf", key: key, title: key),
            unreadChapterCount: unread, finishedReadingAt: finished)
    }
}
