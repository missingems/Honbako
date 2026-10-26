@testable import Sumi
import AidokuRunner
import Testing

@Suite struct SumiChapterSnapshotTests {
    @Test("Completed history stays read even if a stored page remains")
    func completedChapter() {
        let chapter = snapshot(completed: true, page: 14, total: 20)
        #expect(chapter.progressLabel == "Read")
        #expect(chapter.progressFraction == nil)
    }

    @Test("Unfinished progress supports known and unknown page totals")
    func readingProgress() {
        let known = snapshot(page: 7, total: 20, current: true)
        #expect(known.progressLabel == "Page 7 of 20")
        #expect(known.progressFraction == 0.35)
        let unknown = snapshot(page: 7, total: nil)
        #expect(unknown.progressLabel == "Page 7")
        #expect(unknown.progressFraction == nil)
        #expect(snapshot(page: 25, total: 20).progressFraction == 1)
    }

    @Test("The next unread chapter has no invented page progress")
    func unreadChapter() {
        let next = snapshot(current: true)
        #expect(next.progressLabel == "Next to read")
        #expect(next.progressFraction == nil)
        #expect(snapshot().progressLabel == "Unread")
        #expect(next.title == "Chapter 3.5")
        #expect(next.subtitle == "The return · Fixture group")
    }

    private func snapshot(completed: Bool = false, page: Int? = nil,
                          total: Int? = nil, current: Bool = false) -> SumiChapterSnapshot {
        SumiChapterSnapshot(
            id: ChapterIdentifier(sourceKey: "fixture", mangaKey: "book", chapterKey: "chapter"),
            chapter: AidokuRunner.Chapter(key: "chapter", title: "The return", chapterNumber: 3.5,
                                         scanlators: ["Fixture group"]),
            completed: completed, currentPage: page, totalPages: total,
            isCurrent: current, canRead: true
        )
    }
}
