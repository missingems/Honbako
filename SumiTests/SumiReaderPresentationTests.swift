@testable import Sumi
import AidokuRunner
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiReaderPresentationTests {
    @Test("Paper stays full bleed under every asymmetric system bar inset")
    func fullBleedPaper() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 700)
        for insets in [UIEdgeInsets.zero, UIEdgeInsets(top: 24, left: 51, bottom: 34, right: 84)] {
            #expect(SumiReaderPresentation.contentFrame(in: bounds, safeAreaInsets: insets) == bounds)
        }
    }

    @Test("Every viewport uses Fit even when a previous Fill override is supplied")
    func explicitSizingPolicy() {
        for override in [ReaderPageSizing.fit, .fill] {
            let wide = SumiReaderPresentation.resolve(viewport: CGSize(width: 1000, height: 700),
                readingMode: .ltr, reduceMotion: false, sizingOverride: override)
            let tall = SumiReaderPresentation.resolve(viewport: CGSize(width: 450, height: 700),
                readingMode: .ltr, reduceMotion: false, sizingOverride: override)
            #expect(wide.pageSizing == .fit)
            #expect(tall.pageSizing == .fit)
            #expect(wide.usesDoublePages && wide.usesCustomCurl)
            #expect(!tall.usesDoublePages && !tall.usesCustomCurl)
        }
    }

    @Test("Choosing the second leaf keeps its exact canonical page through fit changes and folding")
    func canonicalFocusSurvivesFold() async throws {
        let store = ReaderTemporaryPageStore()
        let reader = ReaderPagedViewController(source: nil,
            manga: .init(sourceKey: "sumi-test", key: "canonical-focus", title: "Canonical focus"),
            temporaryPageStore: store)
        let delegate = SumiCanonicalFocusDelegate()
        reader.delegate = delegate
        reader.readingMode = .ltr
        let chapter = AidokuRunner.Chapter(key: "canonical-focus")
        reader.chapter = chapter
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        window.rootViewController = reader
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
            Task { await store.removeAll() }
        }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
        }
        reader.viewModel.pages = (0..<8).map {
            .init(sourceId: "sumi-test", chapterId: chapter.id, index: $0, image: image)
        }
        reader.loadPageControllers(chapter: chapter)
        reader.loadPages(in: 1...8)
        try await settle(reader, window: window)
        reader.sumiMove(toCanonicalPage: 6)
        try await settle(reader, window: window)
        let wide = try pager(in: reader)
        let spread = try #require(wide.viewControllers?.first as? ReaderBookSpreadViewController)
        #expect(reader.visibleActualPageRange(in: spread) == 5...6)
        #expect(reader.sumiCurrentCanonicalPage == 6)
        #expect(delegate.reports.last == 6...6)
        reader.sumiSetPageSizing(.fit)
        try await settle(reader, window: window)
        #expect(reader.sumiCurrentCanonicalPage == 6)
        window.frame.size = CGSize(width: 450, height: 700)
        try await settle(reader, window: window)
        let portrait = try pager(in: reader)
        #expect(!(portrait is SumiPageCurlViewController))
        #expect(portrait.view.accessibilityIdentifier == "sumi.reader.slide")
        #expect(portrait.viewControllers?.first === reader.pageViewControllers[6])
        #expect(reader.sumiCurrentCanonicalPage == 6)
        #expect(delegate.reports.last == 6...6)
        window.frame.size = CGSize(width: 1000, height: 700)
        try await settle(reader, window: window)
        let returnedPager = try pager(in: reader)
        let returned = try #require(returnedPager.viewControllers?.first as? ReaderBookSpreadViewController)
        #expect(reader.visibleActualPageRange(in: returned) == 5...6)
        #expect(reader.sumiCurrentCanonicalPage == 6)
        #expect(delegate.reports.last == 6...6)
    }

    @Test("Preparing a scrub destination waits for both leaves without moving or reporting progress")
    func prepareCompleteSpreadBeforeMoving() async throws {
        let (reader, window, store, delegate, image) = preparationReader(key: "prepare-both-leaves")
        defer {
            window.isHidden = true
            window.rootViewController = nil
            Task { await store.removeAll() }
        }
        try await settle(reader, window: window)
        let current = try #require(try pager(in: reader).viewControllers?.first)
        let reports = delegate.reports
        #expect(reader.sumiCurrentCanonicalPage == 1)
        #expect(reader.sumiReadyForOpening)
        let first = try #require(reader.pageViewControllers[3].pageView)
        let partner = try #require(reader.pageViewControllers[4].pageView)
        first.setPageImage(nil)
        partner.setPageImage(nil)

        var result: Bool?
        let preparation = Task { @MainActor in
            let ready = await reader.sumiPrepareCanonicalPage(3)
            result = ready
            return ready
        }
        defer { preparation.cancel() }
        try await Task.sleep(for: .milliseconds(80))
        #expect(result == nil)
        first.setPageImage(image)
        try await Task.sleep(for: .milliseconds(80))
        #expect(result == nil, "A loaded requested page cannot substitute for its missing partner")
        #expect(reader.sumiCurrentCanonicalPage == 1)
        #expect(delegate.reports == reports)
        #expect(try pager(in: reader).viewControllers?.first === current)

        partner.setPageImage(image)
        #expect(await preparation.value)
        #expect(reader.sumiCurrentCanonicalPage == 1)
        #expect(delegate.reports == reports)
        #expect(try pager(in: reader).viewControllers?.first === current)

        reader.sumiMove(toCanonicalPage: 3)
        try await settle(reader, window: window)
        #expect(reader.sumiCurrentCanonicalPage == 3)
        #expect(reader.sumiReadyForOpening)
        partner.setPageImage(nil)
        #expect(!reader.sumiReadyForOpening, "Visible readiness requires the whole spread, not just page 3")
        partner.setPageImage(image)
        #expect(!reader.sumiReadyForOpening, "A late visible leaf becomes ready after its fade")
        let revealDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !reader.sumiReadyForOpening, ContinuousClock.now < revealDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(reader.sumiReadyForOpening)
    }

    @Test("Canceling a pending scrub preparation retains the current spread and history")
    func cancelSpreadPreparation() async throws {
        let (reader, window, store, delegate, image) = preparationReader(key: "cancel-preparation")
        defer {
            window.isHidden = true
            window.rootViewController = nil
            Task { await store.removeAll() }
        }
        try await settle(reader, window: window)
        let current = try #require(try pager(in: reader).viewControllers?.first)
        let reports = delegate.reports
        let partner = try #require(reader.pageViewControllers[4].pageView)
        partner.setPageImage(nil)
        var result: Bool?
        let preparation = Task { @MainActor in
            let ready = await reader.sumiPrepareCanonicalPage(3)
            result = ready
            return ready
        }
        defer { preparation.cancel() }
        try await Task.sleep(for: .milliseconds(80))
        #expect(result == nil)
        preparation.cancel()
        #expect(!(await preparation.value))
        partner.setPageImage(image)
        try await Task.sleep(for: .milliseconds(80))
        #expect(reader.sumiCurrentCanonicalPage == 1)
        #expect(delegate.reports == reports)
        #expect(try pager(in: reader).viewControllers?.first === current)
        #expect(reader.sumiReadyForOpening)
    }

    @Test("A new chapter cannot prepare using the previous chapter's loaded spread")
    func rejectStaleChapterPreparation() async throws {
        let (reader, window, store, delegate, _) = preparationReader(key: "previous-chapter")
        defer {
            window.isHidden = true
            window.rootViewController = nil
            Task { await store.removeAll() }
        }
        try await settle(reader, window: window)
        let current = try #require(try pager(in: reader).viewControllers?.first)
        let reports = delegate.reports
        let loadedChapter = try #require(reader.viewModel.chapter)
        #expect(reader.sumiReadyForOpening)
        reader.chapter = AidokuRunner.Chapter(key: "new-chapter")

        #expect(reader.viewModel.chapter?.id == loadedChapter.id)
        #expect(!(await reader.sumiPrepareCanonicalPage(3)))
        #expect(!reader.sumiReadyForOpening)
        #expect(reader.sumiCurrentCanonicalPage == 1)
        #expect(delegate.reports == reports)
        #expect(try pager(in: reader).viewControllers?.first === current)
    }

    @Test("A landscape leaf uses its parent book viewport and respects Reduce Motion")
    func viewportPolicy() {
        let landscape = CGSize(width: 1000, height: 700)
        let book = SumiReaderPresentation.resolve(viewport: landscape, readingMode: .rtl, reduceMotion: false)
        #expect(book.pageSizing == .fit)
        #expect(book.usesDoublePages && book.usesCustomCurl)
        let reduced = SumiReaderPresentation.resolve(viewport: landscape, readingMode: .rtl, reduceMotion: true)
        #expect(reduced.pageSizing == .fit)
        #expect(reduced.usesDoublePages && !reduced.usesCustomCurl)
        for viewport in [CGSize(width: 450, height: 700), CGSize(width: 700, height: 700), .zero] {
            let single = SumiReaderPresentation.resolve(viewport: viewport, readingMode: .ltr, reduceMotion: false)
            #expect(single.pageSizing == .fit)
            #expect(!single.usesDoublePages && !single.usesCustomCurl)
        }
        let vertical = SumiReaderPresentation.resolve(viewport: landscape, readingMode: .vertical, reduceMotion: false)
        #expect(!vertical.usesCustomCurl && !vertical.usesDoublePages)
    }

    @Test("Folding switches between portrait swipe and landscape curl with the same complete artwork")
    func foldAndFit() async throws {
        let store = ReaderTemporaryPageStore()
        defer { Task { await store.removeAll() } }
        var reducedMotion = false
        let reader = ReaderPagedViewController(source: nil,
            manga: .init(sourceKey: "sumi-test", key: "adaptive", title: "Adaptive"),
            temporaryPageStore: store, reduceMotionEnabled: { reducedMotion })
        reader.readingMode = .ltr
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        window.rootViewController = reader
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 1200), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 1200))
            UIColor.black.setFill()
            context.fill(CGRect(x: 20, y: 120, width: 560, height: 960))
        }
        let chapter = AidokuRunner.Chapter(key: "adaptive")
        reader.chapter = chapter
        reader.viewModel.pages = (0..<6).map {
            .init(sourceId: "sumi-test", chapterId: chapter.id, index: $0, image: image)
        }
        reader.loadPageControllers(chapter: chapter)
        reader.loadPages(in: 1...6)
        reader.view.layoutIfNeeded()
        reader.move(toPage: 3, animated: false)
        try await settle(reader, window: window)
        let firstPager = try pager(in: reader)
        #expect(firstPager is SumiPageCurlViewController)
        try assertCompleteLeaves(in: firstPager, image: image)
        #expect(reader.currentPage == 3)
        let paperFrame = firstPager.view.frame
        reader.sumiSetPageSizing(.fill)
        try await settle(reader, window: window)
        #expect(reader.sumiEffectivePageSizing == .fit, "An old Fill command cannot crop Sumi pages")
        try assertCompleteLeaves(in: firstPager, image: image)
        #expect(try pager(in: reader) === firstPager)
        #expect(firstPager.view.frame == paperFrame)
        #expect(reader.currentPage == 3)
        reader.sumiSetPageSizing(.fit)
        try await settle(reader, window: window)
        try assertCompleteLeaves(in: firstPager, image: image)
        #expect(reader.currentPage == 3)
        reader.sumiPageSizingOverride = nil

        // Rotation cancels a held gesture before mounting the new layout.
        // A stale completion from the discarded pager must not undo it.
        let oldControllers = try #require(firstPager.viewControllers)
        let current = try #require(oldControllers.first)
        let pending = try #require(firstPager.dataSource?.pageViewController(firstPager, viewControllerAfter: current))
        reader.pageViewController(firstPager, willTransitionTo: [pending])
        window.frame.size = CGSize(width: 450, height: 700)
        try await settle(reader, window: window)
        #expect(try pager(in: reader) !== firstPager)
        #expect(reader.currentPage == 3)
        reader.pageViewController(firstPager, didFinishAnimating: true,
            previousViewControllers: oldControllers, transitionCompleted: false)
        try await settle(reader, window: window)
        let portraitPager = try pager(in: reader)
        #expect(!(portraitPager is SumiPageCurlViewController))
        #expect(portraitPager.transitionStyle == .scroll)
        #expect(portraitPager.view.accessibilityIdentifier == "sumi.reader.slide")
        let single = try #require(portraitPager.viewControllers?.first as? ReaderPageViewController)
        #expect(single.zoomView?.effectivePageSizing == .fit)
        #expect(single.zoomView?.zoomScale == 1)
        #expect(single.pageView?.imageView.image === image)
        #expect(reader.currentPage == 3)

        window.frame.size = CGSize(width: 1000, height: 700)
        try await settle(reader, window: window)
        let unfolded = try pager(in: reader)
        #expect(unfolded is SumiPageCurlViewController)
        try assertCompleteLeaves(in: unfolded, image: image)
        #expect(reader.currentPage == 3)

        reducedMotion = true
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        try await settle(reader, window: window)
        let reducedPager = try pager(in: reader)
        #expect(!(reducedPager is SumiPageCurlViewController))
        try assertCompleteLeaves(in: reducedPager, image: image)
        #expect(reader.currentPage == 3)
    }

    private func preparationReader(key: String) -> (ReaderPagedViewController, UIWindow, ReaderTemporaryPageStore, SumiCanonicalFocusDelegate, UIImage) {
        let store = ReaderTemporaryPageStore()
        let reader = ReaderPagedViewController(source: nil,
            manga: .init(sourceKey: "sumi-test", key: key, title: "Scrub preparation"),
            temporaryPageStore: store)
        let delegate = SumiCanonicalFocusDelegate()
        reader.delegate = delegate
        reader.readingMode = .ltr
        let chapter = AidokuRunner.Chapter(key: key)
        reader.chapter = chapter
        reader.viewModel.chapter = chapter
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        window.rootViewController = reader
        window.isHidden = false
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
        }
        reader.viewModel.pages = (0..<6).map {
            .init(sourceId: "sumi-test", chapterId: chapter.id, index: $0, image: image)
        }
        reader.loadPageControllers(chapter: chapter)
        reader.loadPages(in: 1...6)
        reader.sumiMove(toCanonicalPage: 1)
        return (reader, window, store, delegate, image)
    }

    private func settle(_ reader: ReaderPagedViewController, window: UIWindow) async throws {
        for _ in 0..<4 {
            window.setNeedsLayout()
            reader.view.setNeedsLayout()
            window.layoutIfNeeded()
            reader.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }
    }

    private func pager(in reader: ReaderPagedViewController) throws -> UIPageViewController {
        try #require(reader.children.compactMap { $0 as? UIPageViewController }.first)
    }

    private func assertCompleteLeaves(in pager: UIPageViewController, image: UIImage) throws {
        let spread = try #require(pager.viewControllers?.first as? ReaderBookSpreadViewController)
        #expect(spread.leaves.count == 2)
        for leaf in spread.leaves {
            let page = try #require(leaf as? ReaderPageViewController)
            let zoom = try #require(page.zoomView)
            let pageView = try #require(page.pageView)
            #expect(zoom.effectivePageSizing == .fit)
            #expect(zoom.baselineZoomScale == 1)
            #expect(zoom.zoomScale == 1)
            #expect(pageView.imageView.image === image)
            let sourceFrame = ReaderPageSizingGeometry.aspectFitFrame(imageSize: image.size, in: pageView.imageView.bounds)
            let frame = pageView.imageView.convert(sourceFrame, to: zoom)
            #expect(frame.minX >= zoom.bounds.minX - 0.5)
            #expect(frame.maxX <= zoom.bounds.maxX + 0.5)
            #expect(frame.minY >= zoom.bounds.minY - 0.5)
            #expect(frame.maxY <= zoom.bounds.maxY + 0.5)
            let original = CGRect(x: 0, y: 0, width: 600, height: 1200)
            #expect(pageView.contentFrameForPageSizing(original, sizing: .fit) == original)
        }
    }
}

@MainActor
private final class SumiCanonicalFocusDelegate: ReaderHoldingDelegate {
    var barsHidden = true
    var reports: [ClosedRange<Int>] = []
    func hideBars() { barsHidden = true }
    func getNextChapter() -> AidokuRunner.Chapter? { nil }
    func getPreviousChapter() -> AidokuRunner.Chapter? { nil }
    func setChapter(_ chapter: AidokuRunner.Chapter) {}
    func setCurrentPage(_ page: Int, position: Double?) { reports.append(page...page) }
    func setCurrentPages(_ pages: ClosedRange<Int>) { reports.append(pages) }
    func setPages(_ pages: [Sumi.Page]) {}
    func displayPage(_ page: Int) {}
    func setSliderOffset(_ offset: CGFloat) {}
    func setCompleted() {}
}
