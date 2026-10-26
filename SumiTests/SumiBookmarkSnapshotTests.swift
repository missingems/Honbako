@testable import Sumi
import AidokuRunner
import Testing

@Suite struct SumiBookmarkSnapshotTests {
    @Test("Completed or empty history cannot become an unfinished bookmark")
    func unavailableBookmark() {
        #expect(SumiBookmarkSnapshot(chapterKey: "saved", page: 18, completed: true) == nil)
        #expect(SumiBookmarkSnapshot(chapterKey: "saved", page: 0, completed: false) == nil)
        #expect(SumiBookmarkSnapshot(chapterKey: "saved", page: -1, completed: false) == nil)
        #expect(SumiBookmarkSnapshot(chapterKey: "", page: 7, completed: false) == nil)
    }

    @Test("An exact saved chapter and page does not require an invented total")
    func exactBookmark() throws {
        let bookmark = try #require(SumiBookmarkSnapshot(chapterKey: "chapter-238", page: 9, completed: false))
        #expect(bookmark.chapterKey == "chapter-238")
        #expect(bookmark.page == 9)
        let manga = AidokuRunner.Manga(sourceKey: "fixture", key: "book", title: "Book")
        let book = SumiBook(manga: manga, bookmark: bookmark)
        #expect(book.hasUnfinishedBookmark)
        #expect(!SumiBook(manga: manga, progress: 1).hasUnfinishedBookmark)
        #expect(!SumiBook(manga: manga, pageLabel: "Completed").hasUnfinishedBookmark)
    }
}
