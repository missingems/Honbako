//
//  ReaderPageViewportTests.swift
//  AidokuTests
//

@testable import Aidoku
import AidokuRunner
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct ReaderPageViewportTests {
    @Test("Artwork uses full bounds in every sizing mode and bar state", arguments: [false, true], ArtworkMode.allCases)
    func artworkUsesFullBounds(isSpread: Bool, mode: ArtworkMode) async throws {
        let store = ReaderTemporaryPageStore()
        do {
            try await withPageSizing(mode.sizing) {
                let delegate = ViewportReaderDelegate(barsHidden: true)
                try await withViewport(isSpread: isSpread, delegate: delegate, store: store) { controller, zoomView, window in
                    #expect(controller.view.safeAreaInsets.bottom >= 34)
                    #expect(controller.view.safeAreaInsets.left >= 80)
                    #expect(zoomView.frame == controller.view.bounds)
                    #expect(zoomView.frame.maxY > controller.view.safeAreaLayoutGuide.layoutFrame.maxY)

                    window.frame.size = CGSize(width: 900, height: 1100)
                    controller.additionalSafeAreaInsets = UIEdgeInsets(top: 16, left: 12, bottom: 40, right: 70)
                    window.layoutIfNeeded()
                    controller.view.layoutIfNeeded()
                    #expect(zoomView.frame == controller.view.bounds)
                }
            }
        } catch {
            await store.removeAll()
            throw error
        }
        await store.removeAll()
    }

    enum ArtworkMode: String, CaseIterable {
        case fit
        case manualZoom
        case fillScrolled

        var sizing: ReaderPageSizing { self == .fillScrolled ? .fill : .fit }
    }

    @Test("Bar and safe-area changes preserve rendered scale and the image reading point", arguments: [false, true], ArtworkMode.allCases)
    func barVisibilityPreservesArtwork(isSpread: Bool, mode: ArtworkMode) async throws {
        let store = ReaderTemporaryPageStore()
        do {
            try await withPageSizing(mode.sizing) {
                let delegate = ViewportReaderDelegate(barsHidden: true)
                try await withViewport(isSpread: isSpread, delegate: delegate, store: store) { controller, zoomView, window in
                    let pages = try await loadArtwork(controller, zoomView: zoomView, window: window)
                    configureReadingPosition(mode, zoomView: zoomView)
                    let baseline = try artworkState(pages, zoomView: zoomView, window: window)
                    if mode == .manualZoom { #expect(abs(zoomView.zoomScale - 2.4) < 0.001) }
                    if mode == .fillScrolled { #expect(zoomView.contentOffset.y > -zoomView.adjustedContentInset.top + 50) }

                    for (index, insets) in [
                        UIEdgeInsets(top: 24, left: 16, bottom: 44, right: 90),
                        UIEdgeInsets(top: 70, left: 100, bottom: 12, right: 8),
                        UIEdgeInsets(top: 20, left: 80, bottom: 34, right: 16)
                    ].enumerated() {
                        // Notifications can arrive before UIKit has finished
                        // changing safe areas, so verify each stage separately.
                        delegate.barsHidden = false
                        NotificationCenter.default.post(name: .readerShowingBars, object: nil)
                        settleLayout(controller, zoomView: zoomView, window: window)
                        try expectArtworkUnchanged(baseline, pages: pages, zoomView: zoomView, window: window)
                        controller.additionalSafeAreaInsets = insets
                        try await settleQueuedLayout(controller, zoomView: zoomView, window: window)
                        try expectArtworkUnchanged(baseline, pages: pages, zoomView: zoomView, window: window)

                        delegate.barsHidden = true
                        NotificationCenter.default.post(name: .readerHidingBars, object: nil)
                        controller.additionalSafeAreaInsets = index.isMultiple(of: 2) ? .zero : insets
                        try await settleQueuedLayout(controller, zoomView: zoomView, window: window)
                        try expectArtworkUnchanged(baseline, pages: pages, zoomView: zoomView, window: window)
                    }
                }
            }
        } catch {
            await store.removeAll()
            throw error
        }
        await store.removeAll()
    }

    @Test("Native opaque and translucent bars preserve the full artwork parent frame", arguments: [false, true], ArtworkMode.allCases)
    func nativeBarsPreserveParentAndArtwork(isSpread: Bool, mode: ArtworkMode) async throws {
        let store = ReaderTemporaryPageStore()
        do {
            try await withPageSizing(mode.sizing) {
                let delegate = ViewportReaderDelegate(barsHidden: false)
                try await withViewport(isSpread: isSpread, delegate: delegate, store: store, nativeNavigation: true) { controller, zoomView, window in
                    let navigation = try #require(controller.navigationController)
                    let pages = try await loadArtwork(controller, zoomView: zoomView, window: window)
                    configureReadingPosition(mode, zoomView: zoomView)
                    let baseline = try artworkState(pages, zoomView: zoomView, window: window)
                    let parentFrame = controller.view.convert(controller.view.bounds, to: window)
                    for translucent in [false, true] {
                        navigation.navigationBar.isTranslucent = translucent
                        navigation.toolbar.isTranslucent = translucent
                        for hidden in [true, false, true, false] {
                            delegate.barsHidden = hidden
                            navigation.setNavigationBarHidden(hidden, animated: false)
                            navigation.setToolbarHidden(hidden, animated: false)
                            NotificationCenter.default.post(name: hidden ? .readerHidingBars : .readerShowingBars, object: nil)
                            try await settleQueuedLayout(controller, zoomView: zoomView, window: window)
                            #expect(navigation.topViewController === controller)
                            #expect(controller.view.convert(controller.view.bounds, to: window) == parentFrame)
                            try expectArtworkUnchanged(baseline, pages: pages, zoomView: zoomView, window: window)
                        }
                    }
                }
            }
        } catch {
            await store.removeAll()
            throw error
        }
        await store.removeAll()
    }

    @Test("Changing Fit and Fill keeps the same full artwork viewport", arguments: [false, true])
    func sizingUpdatesViewport(isSpread: Bool) async throws {
        let store = ReaderTemporaryPageStore()
        do {
            try await withPageSizing(.fit) {
                let delegate = ViewportReaderDelegate(barsHidden: true)
                try await withViewport(isSpread: isSpread, delegate: delegate, store: store) { controller, zoomView, _ in
                    #expect(zoomView.frame == controller.view.bounds)

                    setPageSizing(.fill)
                    controller.view.layoutIfNeeded()
                    #expect(zoomView.frame == controller.view.bounds)

                    setPageSizing(.fit)
                    controller.view.layoutIfNeeded()
                    #expect(zoomView.frame == controller.view.bounds)
                }
            }
        } catch {
            await store.removeAll()
            throw error
        }
        await store.removeAll()
    }

    @Test("Real spread artwork stays at full width and at the reading start through repeated resize")
    func spreadArtworkResize() async throws {
        let store = ReaderTemporaryPageStore()
        do {
            try await withPageSizing(.fill) {
                let delegate = ViewportReaderDelegate(barsHidden: true)
                try await withViewport(isSpread: true, delegate: delegate, store: store) { controller, zoomView, window in
                    let spread = try #require(controller as? ReaderDoublePageViewController)
                    let pageViews = try [spread.firstPageController, spread.secondPageController].map {
                        try #require($0.pageView)
                    }
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1
                    let imageSize = CGSize(width: 200, height: 400)
                    let image = UIGraphicsImageRenderer(size: imageSize, format: format).image { context in
                        context.cgContext.setFillColor(UIColor.white.cgColor)
                        context.cgContext.fill(CGRect(origin: .zero, size: imageSize))
                    }
                    for pageView in pageViews {
                        pageView.imageView.image = image
                        pageView.fixImageSize()
                    }
                    settleLayout(controller, zoomView: zoomView, window: window)
                    zoomView.updatePageSizing(resetZoom: true)

                    for size in [
                        CGSize(width: 1100, height: 900), CGSize(width: 1400, height: 900),
                        CGSize(width: 1000, height: 700), CGSize(width: 1100, height: 900)
                    ] {
                        window.frame.size = size
                        settleLayout(controller, zoomView: zoomView, window: window)
                        let frames = pageViews.map { pageView in
                            let drawnFrame = ReaderPageSizingGeometry.aspectFitFrame(
                                imageSize: imageSize, in: pageView.imageView.bounds
                            )
                            return pageView.imageView.convert(drawnFrame, to: zoomView)
                        }
                        let artwork = frames[0].union(frames[1]).offsetBy(
                            dx: -zoomView.contentOffset.x, dy: -zoomView.contentOffset.y
                        )
                        #expect(abs(artwork.minX) < 0.5)
                        #expect(abs(artwork.maxX - zoomView.bounds.width) < 0.5)
                        #expect(abs(artwork.minY) < 0.5)
                        #expect(zoomView.frame == controller.view.bounds)
                    }
                }
            }
        } catch {
            await store.removeAll()
            throw error
        }
        await store.removeAll()
    }

    private struct ArtworkState {
        let frames: [CGRect]
        let imageCoordinates: [CGPoint]
        let images: [UIImage]
        let viewport: CGRect
        let zoomScale: CGFloat
    }

    private func loadArtwork(_ controller: UIViewController, zoomView: ZoomableScrollView, window: UIWindow) async throws -> [ReaderPageView] {
        let pageControllers: [ReaderPageViewController]
        if let spread = controller as? ReaderDoublePageViewController {
            pageControllers = [spread.firstPageController, spread.secondPageController]
        } else {
            pageControllers = [try #require(controller as? ReaderPageViewController)]
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 200, height: 800)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            context.fill(CGRect(x: 40, y: 250, width: 120, height: 30))
            // Distinct edges make this a complete page rather than a blank
            // placeholder while its drawn image geometry is measured.
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: 8))
            context.fill(CGRect(x: 0, y: size.height - 8, width: size.width, height: 8))
            context.fill(CGRect(x: 0, y: 0, width: 8, height: size.height))
            context.fill(CGRect(x: size.width - 8, y: 0, width: 8, height: size.height))
        }
        let pages = try pageControllers.map { try #require($0.pageView) }
        if controller is ReaderDoublePageViewController {
            // Use the real image-loading path while excluding unrelated
            // persisted crop/downsample/upscale settings from this layout test.
            for (index, page) in pages.enumerated() {
                let loaded = await page.setPage(
                    Page(sourceId: "viewport-test", chapterId: "spread-\(index)", image: image), skipProcessing: true
                )
                #expect(loaded)
            }
        } else {
            pageControllers[0].setPage(Page(sourceId: "viewport-test", chapterId: "single", image: image), skipProcessing: true)
        }
        for _ in 0..<50 {
            if pages.allSatisfy({ $0.imageView.image != nil }) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        for page in pages { _ = try #require(page.imageView.image) }
        try await settleQueuedLayout(controller, zoomView: zoomView, window: window)
        zoomView.updatePageSizing(resetZoom: true)
        try await settleQueuedLayout(controller, zoomView: zoomView, window: window)
        return pages
    }

    private func configureReadingPosition(_ mode: ArtworkMode, zoomView: ZoomableScrollView) {
        if mode == .manualZoom {
            zoomView.setZoomScale(2.4, animated: false)
            let x = max(-zoomView.adjustedContentInset.left, (zoomView.contentSize.width - zoomView.bounds.width) / 2 + 40)
            let y = max(-zoomView.adjustedContentInset.top, (zoomView.contentSize.height - zoomView.bounds.height) / 3)
            zoomView.setContentOffset(CGPoint(x: x, y: y), animated: false)
        } else if mode == .fillScrolled {
            let minimum = -zoomView.adjustedContentInset.top
            let maximum = zoomView.contentSize.height - zoomView.bounds.height + zoomView.adjustedContentInset.bottom
            zoomView.setContentOffset(CGPoint(x: -zoomView.adjustedContentInset.left, y: minimum + (maximum - minimum) * 0.35), animated: false)
        }
    }

    private func artworkState(_ pages: [ReaderPageView], zoomView: ZoomableScrollView, window: UIWindow) throws -> ArtworkState {
        let images = try pages.map { try #require($0.imageView.image) }
        let reference = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
        let frames = zip(pages, images).map { page, image in
            let frame = ReaderPageSizingGeometry.aspectFitFrame(imageSize: image.size, in: page.imageView.bounds)
            return page.imageView.convert(frame, to: window)
        }
        let imageCoordinates = zip(pages, images).map { page, image in
            let frame = ReaderPageSizingGeometry.aspectFitFrame(imageSize: image.size, in: page.imageView.bounds)
            let point = page.imageView.convert(reference, from: window)
            return CGPoint(x: (point.x - frame.minX) / frame.width, y: (point.y - frame.minY) / frame.height)
        }
        return ArtworkState(frames: frames, imageCoordinates: imageCoordinates, images: images,
                            viewport: zoomView.convert(zoomView.bounds, to: window), zoomScale: zoomView.zoomScale)
    }

    private func expectArtworkUnchanged(_ expected: ArtworkState, pages: [ReaderPageView], zoomView: ZoomableScrollView, window: UIWindow) throws {
        let actual = try artworkState(pages, zoomView: zoomView, window: window)
        let pixel = 1 / max(1, window.traitCollection.displayScale)
        #expect(zoomView.frame == zoomView.superview?.bounds)
        #expect(actual.viewport == expected.viewport)
        #expect(abs(actual.zoomScale - expected.zoomScale) < 0.001)
        for index in expected.frames.indices {
            let first = expected.frames[index]
            let second = actual.frames[index]
            #expect(abs(first.minX - second.minX) <= pixel)
            #expect(abs(first.minY - second.minY) <= pixel)
            #expect(abs(first.width - second.width) <= pixel)
            #expect(abs(first.height - second.height) <= pixel)
            #expect(abs(actual.imageCoordinates[index].x - expected.imageCoordinates[index].x) * first.width <= pixel)
            #expect(abs(actual.imageCoordinates[index].y - expected.imageCoordinates[index].y) * first.height <= pixel)
            #expect(actual.images[index] === expected.images[index])
        }
    }

    private func settleQueuedLayout(_ controller: UIViewController, zoomView: ZoomableScrollView, window: UIWindow) async throws {
        settleLayout(controller, zoomView: zoomView, window: window)
        try await Task.sleep(nanoseconds: 20_000_000)
        settleLayout(controller, zoomView: zoomView, window: window)
    }

    private func settleLayout(_ controller: UIViewController, zoomView: ZoomableScrollView, window: UIWindow) {
        for _ in 0..<4 {
            window.setNeedsLayout()
            controller.view.setNeedsLayout()
            zoomView.setNeedsLayout()
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            zoomView.layoutIfNeeded()
        }
    }

    private func withPageSizing(_ sizing: ReaderPageSizing, perform body: () async throws -> Void) async rethrows {
        let key = AppSettings.reader.pageSizing.key
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            UserDefaults.standard.set(previous, forKey: key)
            NotificationCenter.default.post(name: .init(key), object: nil)
        }
        setPageSizing(sizing)
        try await body()
    }

    private func setPageSizing(_ sizing: ReaderPageSizing) {
        AppSettings.reader.pageSizing.set(sizing)
        NotificationCenter.default.post(name: .init(AppSettings.reader.pageSizing.key), object: nil)
    }

    private func withViewport(
        isSpread: Bool,
        delegate: ViewportReaderDelegate,
        store: ReaderTemporaryPageStore,
        nativeNavigation: Bool = false,
        perform body: (UIViewController, ZoomableScrollView, UIWindow) async throws -> Void
    ) async throws {
        let first = ReaderPageViewController(type: .page, delegate: delegate, temporaryPageStore: store)
        let controller: UIViewController
        let zoomView: ZoomableScrollView
        if isSpread {
            let second = ReaderPageViewController(type: .page, delegate: delegate, temporaryPageStore: store)
            let spread = ReaderDoublePageViewController(firstPage: first, secondPage: second, direction: .ltr)
            spread.loadViewIfNeeded()
            controller = spread
            zoomView = spread.zoomView
        } else {
            first.loadViewIfNeeded()
            controller = first
            zoomView = try #require(first.zoomView)
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1100, height: 900))
        if nativeNavigation {
            // Match the full-art contract supplied by ReaderViewController,
            // without starting its source requests or reading-history tasks.
            controller.edgesForExtendedLayout = .all
            controller.extendedLayoutIncludesOpaqueBars = true
            controller.navigationItem.title = "Reader viewport"
            controller.toolbarItems = [UIBarButtonItem(title: "Page", style: .plain, target: nil, action: nil)]
            let navigation = UINavigationController(rootViewController: controller)
            window.rootViewController = navigation
            navigation.setToolbarHidden(false, animated: false)
        } else {
            window.rootViewController = controller
        }
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 20, left: 80, bottom: 34, right: 16)
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        try await body(controller, zoomView, window)
    }
}

private final class ViewportReaderDelegate: ReaderHoldingDelegate {
    var barsHidden: Bool

    init(barsHidden: Bool) {
        self.barsHidden = barsHidden
    }

    func hideBars() { barsHidden = true }
    func getNextChapter() -> AidokuRunner.Chapter? { nil }
    func getPreviousChapter() -> AidokuRunner.Chapter? { nil }
    func setChapter(_ chapter: AidokuRunner.Chapter) {}
    func setCurrentPage(_ page: Int, position: Double?) {}
    func setCurrentPages(_ pages: ClosedRange<Int>) {}
    func setPages(_ pages: [Aidoku.Page]) {}
    func displayPage(_ page: Int) {}
    func setSliderOffset(_ offset: CGFloat) {}
    func setCompleted() {}
}
