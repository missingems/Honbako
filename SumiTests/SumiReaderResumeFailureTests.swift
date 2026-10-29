@testable import Sumi
import AidokuRunner
import AsyncDisplayKit
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiReaderResumeFailureTests {
    @Test("A saved failed page opens in place with retry controls in portrait and a full spread")
    func savedFailedPageRemainsAccessible() async throws {
        try await withReaderSettings {
            for size in [CGSize(width: 450, height: 800), CGSize(width: 1000, height: 700)] {
                let (reader, window, image) = try fixture(size: size)
                defer { window.isHidden = true; window.rootViewController = nil }
                let paged = try #require(reader.reader as? ReaderPagedViewController)
                try await wait { paged.sumiOpeningImageFailed }
                #expect(paged.sumiCurrentCanonicalPage == 7)
                #expect(reader.sumiCurrentCanonicalPage == 7)
                #expect(!paged.sumiReadyForOpening, "A retry surface cannot stand in for decoded artwork during a curl")
                // A fast failure on one leaf can precede its partner's image
                // reveal. Opening readiness belongs to the entire spread.
                try await wait { paged.sumiCanPresentOpening }
                #expect(paged.sumiCanPresentOpening)
                #expect(await reader.sumiWaitForOpening())
                #expect(reader.sumiOpeningFailureMessage == nil)
                #expect(reader.chapter.key == "saved-chapter")
                reader.sumiDidOpenPreparedBook()
                #expect(reader.sumiCurrentCanonicalPage == 7)

                let failed = try #require(paged.pageViewControllers.first { $0.page?.index == 6 })
                failed.pageView?.setPageImage(image)
                try await wait { paged.sumiReadyForOpening }
                #expect(paged.sumiCurrentCanonicalPage == 7, "A successful retry must not reset the bookmark to page one")
                paged.sumiMove(toCanonicalPage: 3)
                try await wait { paged.sumiReadyForOpening }
                #expect(paged.sumiCurrentCanonicalPage == 3, "A recovered book remains navigable")
                reader.sumiAbandonOpening()
            }
        }
    }

    @Test("Pending images and a previous chapter cannot satisfy saved-page recovery readiness")
    func requiresSelectedChapterAndTerminalSurface() async throws {
        try await withReaderSettings {
            let (reader, window, image) = try fixture(size: CGSize(width: 1000, height: 700))
            defer { window.isHidden = true; window.rootViewController = nil }
            let paged = try #require(reader.reader as? ReaderPagedViewController)
            try await wait { paged.sumiOpeningImageFailed }
            let chapter = try #require(paged.viewModel.chapter)
            paged.viewModel.chapter = .init(key: "another-chapter")
            #expect(!paged.sumiCanPresentOpening, "An error left over from another chapter must not open this book")
            #expect(!paged.sumiCanPresentLoadingOpening)
            paged.viewModel.chapter = chapter
            let selected = try #require(paged.pageViewControllers.first { $0.page?.index == 6 }?.pageView)
            selected.setPageImage(nil)
            #expect(!paged.sumiCanPresentOpening, "A loaded partner cannot substitute for a selected page still loading")
            #expect(paged.sumiCanPresentLoadingOpening, "The actual selected page has its own mounted loading surface")
            #expect(await reader.sumiWaitForOpening(imageWarmup: .zero),
                    "Once the warmup ends, a pending image must not strand a bookmark behind whole-book loading")
            selected.setPageImage(image)
            try await wait { paged.sumiReadyForOpening }
            #expect(paged.sumiCanPresentOpening)
            reader.sumiAbandonOpening()
        }
    }

    @Test("A vertical reader resumes its failed page instead of accepting a nearby decoded page")
    func verticalFailedPageRemainsAccessible() async throws {
        try await withReaderSettings {
            let (reader, window, _) = try fixture(size: CGSize(width: 450, height: 800), vertical: true)
            defer { window.isHidden = true; window.rootViewController = nil }
            let vertical = try #require(reader.reader as? ReaderWebtoonViewController)
            try await wait({
                vertical.sumiOpeningImageFailed && vertical.sumiCurrentCanonicalPage == 7 && vertical.sumiCanPresentOpening
            }, diagnostics: { verticalDiagnostics(vertical) })
            let resumedPath = IndexPath(item: 7, section: 0)
            let frame = try #require(vertical.collectionNode.collectionViewLayout.layoutAttributesForItem(at: resumedPath)?.frame)
            #expect(abs(frame.minY - vertical.scrollView.contentOffset.y) <= 0.5,
                    "The actual viewport must align with page 7, not merely report its index")
            #expect(await reader.sumiWaitForOpening())
            #expect(reader.sumiOpeningFailureMessage == nil)
            #expect(reader.chapter.key == "saved-chapter")
            reader.sumiDidOpenPreparedBook()
            #expect(reader.sumiCurrentCanonicalPage == 7)

            let earlier = try #require(vertical.collectionNode.nodeForItem(at: IndexPath(item: 6, section: 0))
                as? ReaderWebtoonPageNode)
            let originalY = frame.minY
            earlier.image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 1400)).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 400, height: 1400))
            }
            earlier.displayPage()
            try await wait({
                guard let updated = vertical.collectionNode.collectionViewLayout.layoutAttributesForItem(at: resumedPath)?.frame
                else { return false }
                return updated.minY > originalY + 100
                    && abs(updated.minY - vertical.scrollView.contentOffset.y) <= 0.5
                    && vertical.sumiCurrentCanonicalPage == 7
            }, diagnostics: { verticalDiagnostics(vertical) })
            vertical.sumiMove(toCanonicalPage: 9)
            vertical.collectionNode.collectionViewLayout.invalidateLayout()
            vertical.collectionNode.view.layoutIfNeeded()
            #expect(vertical.sumiIsCanonicalPageVisible(9))
            #expect(vertical.sumiCurrentCanonicalPage == 9,
                    "An explicit move must release the initial bookmark hold")
            reader.sumiAbandonOpening()
        }
    }

    @Test("A chapter reload failure keeps one retry surface instead of adding an alert over it")
    func chapterFailureDoesNotOverlayAnotherError() async throws {
        try await withReaderSettings {
            let (reader, window, _) = try fixture(size: CGSize(width: 450, height: 800))
            defer { window.isHidden = true; window.rootViewController = nil }
            let paged = try #require(reader.reader as? ReaderPagedViewController)
            try await wait { paged.sumiCanPresentOpening }
            reader.sumiDidOpenPreparedBook()
            paged.viewModel.sumiPageLoaderOverride = { _ in [] }
            paged.setChapter(reader.chapter, startPage: 7)
            try await wait { reader.pages.isEmpty }
            #expect(reader.presentedViewController == nil)
            #expect(reader.chapter.key == "saved-chapter")
            #expect(reader.sumiOpeningFailureMessage == nil)
            reader.sumiAbandonOpening()
        }
    }

    @Test("A final saved page stays incomplete while failed or pending and becomes eligible only after its image arrives")
    func pendingFinalPageCannotCompleteChapter() async throws {
        try await withReaderSettings {
            let (reader, window, image) = try fixture(size: CGSize(width: 450, height: 800), startPage: 12, failedPage: 12)
            defer { window.isHidden = true; window.rootViewController = nil }
            let paged = try #require(reader.reader as? ReaderPagedViewController)
            try await wait { paged.sumiOpeningImageFailed }
            reader.sumiDidOpenPreparedBook()
            #expect(reader.sumiCurrentCanonicalPage == 12)
            #expect(!reader.sumiCanCompleteVisibleChapter)
            let selected = try #require(paged.pageViewControllers.first { $0.page?.index == 11 }?.pageView)
            selected.setPageImage(nil)
            #expect(!paged.sumiOpeningImageFailed)
            #expect(!reader.sumiCanCompleteVisibleChapter, "A pending bitmap must not complete the chapter after warmup")
            #expect(await reader.sumiWaitForOpening(imageWarmup: .zero))
            selected.setPageImage(image)
            try await wait { reader.sumiCanCompleteVisibleChapter }
            #expect(reader.sumiCurrentCanonicalPage == 12)
            #expect(paged.sumiCanCompleteVisibleChapter)
            paged.sumiMove(toCanonicalPage: 3)
            try await wait { paged.sumiReadyForOpening }
            #expect(!reader.sumiCanCompleteVisibleChapter, "A decoded final page held offscreen cannot complete another position")
            reader.sumiAbandonOpening()
        }
    }

    @Test("An empty chapter response is retryable without replacing the selected chapter")
    func emptyMetadataCanRetry() async {
        let manga = AidokuRunner.Manga(sourceKey: "sumi-recovery-test", key: "empty-retry", title: "Empty retry fixture")
        let model = ReaderPagedViewModel(source: nil, manga: manga)
        let chapter = AidokuRunner.Chapter(key: "saved-chapter")
        var attempts = 0
        model.sumiPageLoaderOverride = { selected in
            attempts += 1
            return attempts == 1 ? [] : [.init(sourceId: manga.sourceKey, chapterId: selected.key, index: 0)]
        }
        #expect(await model.loadPages(chapter: chapter))
        #expect(model.pages.isEmpty)
        #expect(await model.loadPages(chapter: chapter))
        #expect(attempts == 2)
        #expect(model.chapter?.key == chapter.key)
        #expect(model.pages.first?.chapterId == chapter.key)
    }

    private func fixture(size: CGSize, vertical: Bool = false, startPage: Int = 7, failedPage: Int = 7) throws
        -> (ReaderViewController, UIWindow, UIImage) {
        let chapter = AidokuRunner.Chapter(key: "saved-chapter", chapterNumber: 1, language: "en")
        var manga = AidokuRunner.Manga(sourceKey: "sumi-recovery-test", key: UUID().uuidString, title: "Resume test")
        manga.chapters = [chapter]
        manga.viewer = vertical ? .webtoon : .leftToRight
        let reader = ReaderViewController(source: nil, manga: manga, chapter: chapter, startPage: startPage)
        reader.sumiIsPreparingOpening = true
        let container = SumiDirectReaderController(content: UIViewController())
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = container
        window.isHidden = false
        container.show(reader)
        window.layoutIfNeeded()
        reader.view.layoutIfNeeded()
        let model = try #require((reader.reader as? ReaderPagedViewController)?.viewModel
            ?? (reader.reader as? ReaderWebtoonViewController)?.viewModel)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 800)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 800))
        }
        model.sumiPageLoaderOverride = { selected in
            (0..<12).map { index in
                .init(sourceId: manga.sourceKey, chapterId: selected.key, index: index, image: index + 1 == failedPage ? nil : image)
            }
        }
        return (reader, window, image)
    }

    private func verticalDiagnostics(_ reader: ReaderWebtoonViewController) -> String {
        let visible = reader.collectionNode.visibleNodes.compactMap { $0 as? ReaderWebtoonPageNode }
        let target = reader.collectionNode.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 7, section: 0))?.frame
        return "page=\(reader.sumiCurrentCanonicalPage), offsetY=\(reader.scrollView.contentOffset.y), target=\(String(describing: target)), "
            + "visible=\(visible.map { $0.page.index + 1 }), failed=\(visible.filter(\.sumiImageLoadFailed).map { $0.page.index + 1 })"
    }

    private func wait(_ condition: () -> Bool, diagnostics: (() -> String)? = nil) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try #require(condition(), "\(diagnostics?() ?? "Reader condition did not settle")")
    }

    private func withReaderSettings(_ run: () async throws -> Void) async throws {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var overrides = original
        overrides["General.incognitoMode"] = true
        overrides["Reader.liveText"] = false
        overrides["Reader.verticalInfiniteScroll"] = false
        defaults.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        try await run()
    }
}
