@testable import Sumi
import AidokuRunner
import Foundation
import Testing

struct SumiSearchResultPresentationTests {
    @Test("Unread results become READ only after library membership changes")
    func getThenRead() {
        let book = SumiBook(manga: .init(sourceKey: "test", key: "unread", title: "Unread"))
        #expect(SumiSearchResultPresentation(book: book, isInLibrary: false).action == .get)
        #expect(SumiSearchResultPresentation(book: book, isInLibrary: true).action == .read)
        #expect(SumiSearchResultPresentation(book: book, isInLibrary: true).readingPosition == nil)
        #expect(SumiSearchResultPresentation(book: book, isInLibrary: false).action == .get,
                "A failed add must retain Add instead of changing local action state")
    }

    @Test("Read history offers RESUME even when the title was never added")
    func historyWins() {
        let book = SumiBook(manga: .init(sourceKey: "test", key: "read", title: "Read"),
            chapterLabel: "Chapter 2", pageLabel: "Page 4 of 8", lastRead: .now,
            bookmark: .init(chapterKey: "chapter-2", page: 4, completed: false))
        for saved in [false, true] {
            let presentation = SumiSearchResultPresentation(book: book, isInLibrary: saved)
            #expect(presentation.action == .resume)
            #expect(presentation.readingPosition == "Chapter 2-4")
            #expect(presentation.readingPosition?.contains("of 8") == false)
        }
    }

    @Test("A completed chapter keeps its actual last page without an unfinished bookmark")
    func completedPosition() {
        let book = SumiBook(manga: .init(sourceKey: "test", key: "complete", title: "Complete"),
            chapterLabel: "Chapter 12", pageLabel: "Completed", progress: 1, lastReadPage: 30)
        let presentation = SumiSearchResultPresentation(book: book, isInLibrary: true)
        #expect(presentation.action == .resume)
        #expect(presentation.readingPosition == "Chapter 12-30")
    }

    @Test("Publication metadata displays only the precision actually supplied")
    func publicationPrecision() {
        let manga = AidokuRunner.Manga(sourceKey: "test", key: "year", title: "Title", authors: ["Author"])
        #expect(SumiBook(manga: manga).releaseDateLabel == nil)
        #expect(SumiBook(manga: manga, releaseYear: 2009).releaseDateLabel == "Released 2009")
        #expect(SumiBook(manga: manga, releaseYear: 0).releaseDateLabel == nil)
        #expect(SumiBook(manga: manga, releaseYear: 2009).author == "Author")
    }

    @Test("Publication badges distinguish completed titles from every other non-ongoing status")
    func ongoingSubtitle() {
        var manga = AidokuRunner.Manga(sourceKey: "test", key: "status", title: "Title")
        let unknown = SumiBook(manga: manga)
        #expect(SumiSearchResultPresentation(book: unknown, isInLibrary: false).publicationSubtitle == nil)
        #expect(SumiSearchResultPresentation(book: unknown, isInLibrary: false).publicationBadge == nil)
        #expect(SumiSearchResultPresentation(book: unknown, isInLibrary: false,
            releaseYear: 2009, isOngoing: true).publicationSubtitle == "Released 2009")
        #expect(SumiSearchResultPresentation(book: unknown, isInLibrary: false,
            releaseYear: 2009, isOngoing: true).compactPublicationSubtitle == "2009")
        #expect(SumiSearchResultPresentation(book: SumiBook(manga: manga, releaseYear: 0), isInLibrary: false,
            releaseYear: 2009, isOngoing: true).compactPublicationSubtitle == "2009")
        for status in [AidokuRunner.PublishingStatus.unknown, .hiatus, .cancelled] {
            manga.status = status
            #expect(SumiSearchResultPresentation(book: SumiBook(manga: manga), isInLibrary: false,
                isOngoing: false).publicationBadge == nil)
        }
        manga.status = .ongoing
        #expect(SumiSearchResultPresentation(book: SumiBook(manga: manga), isInLibrary: false).publicationBadge == "Ongoing")
        manga.status = .completed
        let completed = SumiSearchResultPresentation(book: SumiBook(manga: manga, releaseYear: 2012), isInLibrary: true,
            releaseYear: 2009, publishingStatus: .ongoing)
        #expect(completed.publicationBadge == "Finished")
        #expect(completed.publicationSubtitle == "Released 2012",
            "A known source status takes precedence over enriched metadata")
        #expect(SumiSearchResultPresentation(book: unknown, isInLibrary: false,
            publishingStatus: .completed).publicationBadge == "Finished")
        #expect(SumiSearchResultPresentation(book: unknown, isInLibrary: false,
            publishingStatus: .hiatus).publicationBadge == nil)
    }

    @Test("Resume captions preserve fractional or signed source chapter labels and append the page")
    func compactSourceChapterPosition() {
        for chapter in ["Chapter 2", "Chapter 2.5", "Chapter -1", "Volume 3, Chapter 2"] {
            let book = SumiBook(manga: .init(sourceKey: "test", key: "chapter", title: "Title"),
                chapterLabel: chapter, lastRead: .now, lastReadPage: 19)
            #expect(SumiSearchResultPresentation(book: book, isInLibrary: true).readingPosition == "\(chapter)-19")
        }
    }
}
