import AsyncDisplayKit
@testable import Sumi
import AidokuRunner
import Testing
import UIKit

@MainActor
@Suite struct HonbakoPageCoachingReaderCaptureTests {
    @Test("A prepared reader cannot share a page before it is actually presented")
    func unpresentedReaderCannotCapture() {
        let chapter = AidokuRunner.Chapter(key: "chapter", language: "ja")
        let manga = AidokuRunner.Manga(sourceKey: "coaching-capture-test", key: "book", title: "Test", chapters: [chapter])
        let reader = ReaderViewController(source: nil, manga: manga, chapter: chapter)
        #expect(!reader.isViewLoaded)
        #expect(reader.sumiPageCoachingCapture() == nil)
        #expect(!reader.isViewLoaded, "Capture must not load hidden reader UI")
    }

    @Test("Prefetched paged artwork is not a visible-page sharing permission")
    func offscreenPagedImagesStayPrivate() {
        let fixture = fixture()
        let reader = ReaderPagedViewController(source: nil, manga: fixture.manga, temporaryPageStore: ReaderTemporaryPageStore())
        reader.viewModel.chapter = fixture.chapter
        reader.viewModel.pages = [fixture.page]
        reader.viewModel.preloadedChapter = .init(key: "next", language: "ja")
        reader.viewModel.preloadedPages = [fixture.page]
        #expect(!reader.isViewLoaded)
        #expect(reader.sumiVisiblePageForCoaching() == nil)
        #expect(!reader.isViewLoaded)
    }

    @Test("Webtoon page metadata and bitmaps cannot be shared without a visible loaded node")
    func offscreenWebtoonImagesStayPrivate() {
        let fixture = fixture()
        let reader = ReaderWebtoonViewController(source: nil, manga: fixture.manga, temporaryPageStore: ReaderTemporaryPageStore())
        reader.chapter = fixture.chapter
        reader.viewModel.setPages(chapter: fixture.chapter, pages: [fixture.page])
        let wasViewLoaded = reader.isViewLoaded
        #expect(reader.viewIfLoaded?.window == nil)
        #expect(reader.collectionNode.visibleNodes.isEmpty)
        #expect(reader.sumiVisiblePageForCoaching() == nil)
        #expect(reader.isViewLoaded == wasViewLoaded, "Capture must preserve the reader's existing view lifecycle")
    }

    private func fixture() -> (manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter, page: Sumi.Page) {
        let chapter = AidokuRunner.Chapter(key: "chapter", language: "ja")
        let manga = AidokuRunner.Manga(sourceKey: "coaching-capture-test", key: "book", title: "Test", chapters: [chapter])
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { output in
            UIColor.white.setFill()
            output.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return (manga, chapter, Sumi.Page(sourceId: manga.sourceKey, chapterId: chapter.key, index: 0, image: image, language: "ja"))
    }
}
