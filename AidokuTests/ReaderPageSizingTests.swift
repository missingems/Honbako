//
//  ReaderPageSizingTests.swift
//  AidokuTests
//

@testable import Aidoku
import AidokuRunner
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct ReaderPageSizingTests {
    @Test("Fill Width matches artwork width without covering the other viewport axis")
    func sizingGeometry() throws {
        for pageFrame in [
            CGRect(x: 100, y: 0, width: 200, height: 800),
            CGRect(x: 0, y: 300, width: 400, height: 200),
            CGRect(x: -200, y: 300, width: 800, height: 200)
        ] {
            let geometry = try #require(ReaderPageSizingGeometry(
                viewportSize: CGSize(width: 400, height: 800),
                contentSize: CGSize(width: 400, height: 800),
                pageFrame: pageFrame
            ))
            #expect(pageFrame.width * geometry.baselineScale(for: .fill) == 400)
            #expect(geometry.baselineScale(for: .fit) == 1)
        }
    }

    @Test("Choosing Fit again resets manual zoom without replacing page content")
    func fitResetsZoom() {
        let (scrollView, content) = makeScrollView(pageFrame: CGRect(x: 100, y: 0, width: 200, height: 800))
        scrollView.applyPageSizing(.fit, resetZoom: true)
        scrollView.setZoomScale(3, animated: false)
        scrollView.applyPageSizing(.fit, resetZoom: true)

        #expect(scrollView.zoomScale == 1)
        #expect(scrollView.zoomView === content)
        #expect(scrollView.contentOffset == .zero)
    }

    @Test("Fill Width locks zoom while retaining vertical scrolling")
    func widthLocksZoom() {
        let (scrollView, _) = makeScrollView(pageFrame: CGRect(x: 100, y: 0, width: 200, height: 800))
        scrollView.applyPageSizing(.fill, resetZoom: true)
        #expect(scrollView.baselineZoomScale == 2)
        #expect(scrollView.minimumZoomScale == 2)
        #expect(scrollView.maximumZoomScale == 2)
        #expect(scrollView.isScrollEnabled)
        #expect(scrollView.panGestureRecognizer.isEnabled)
        #expect(scrollView.pinchGestureRecognizer?.isEnabled != true)
        #expect(!scrollView.doubleTapEnabled)
        scrollView.zoom(to: CGPoint(x: 200, y: 400), animated: false)
        scrollView.setZoomScale(5, animated: false)
        #expect(scrollView.zoomScale == 2)
    }

    @Test("Tall pages begin at the top and scroll vertically without sideways movement")
    func verticalOnlyScrolling() {
        let frame = CGRect(x: 100, y: 0, width: 200, height: 800)
        let (scrollView, content) = makeScrollView(pageFrame: frame)
        scrollView.applyPageSizing(.fill, resetZoom: true)
        let artwork = content.convert(frame, to: scrollView)
        #expect(scrollView.contentOffset == CGPoint(x: artwork.minX, y: artwork.minY))
        #expect(scrollView.contentSize.width + scrollView.adjustedContentInset.left + scrollView.adjustedContentInset.right == scrollView.bounds.width)
        #expect(scrollView.contentSize.height + scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom == artwork.height)
        let minimumX = -scrollView.adjustedContentInset.left
        let maximumX = scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right
        #expect(minimumX == maximumX)
        #expect(minimumX == artwork.minX)
        scrollView.setContentOffset(CGPoint(x: minimumX, y: 400), animated: false)
        scrollView.layoutIfNeeded()
        #expect(scrollView.contentOffset.y == 400)
        let maximumY = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        scrollView.setContentOffset(CGPoint(x: minimumX, y: maximumY), animated: false)
        scrollView.layoutIfNeeded()
        #expect(scrollView.contentOffset.y == artwork.maxY - scrollView.bounds.height)

        // Explicitly resetting sizing, rather than a scroll callback, repairs a
        // programmatically supplied out-of-range position.
        scrollView.setContentOffset(CGPoint(x: -10000, y: 10000), animated: false)
        scrollView.applyPageSizing(.fill, resetZoom: true)
        #expect(scrollView.contentOffset == CGPoint(x: artwork.minX, y: artwork.minY))
    }

    @Test("Short width-fitted artwork stays centered and has no scrollable extent")
    func shortArtworkCenters() {
        let frame = CGRect(x: 0, y: 300, width: 400, height: 200)
        let (scrollView, content) = makeScrollView(pageFrame: frame)
        scrollView.applyPageSizing(.fill, resetZoom: true)
        let artwork = content.convert(frame, to: scrollView)
        #expect(artwork.width == scrollView.bounds.width)
        #expect(scrollView.contentOffset.y + scrollView.bounds.height / 2 == artwork.midY)
        #expect(scrollView.contentSize.height + scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom == scrollView.bounds.height)
        scrollView.setContentOffset(CGPoint(x: 10000, y: 10000), animated: false)
        scrollView.applyPageSizing(.fill, resetZoom: true)
        #expect(scrollView.contentOffset.y + scrollView.bounds.height / 2 == artwork.midY)
    }

    @Test("Native return animation survives repeated layout without getting stuck overscrolled")
    func verticalBounce() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let host = UIViewController()
        window.rootViewController = host
        host.loadViewIfNeeded()
        let scrollView = ZoomableScrollView(frame: window.bounds)
        host.view.addSubview(scrollView)
        let content = UIView(frame: scrollView.bounds)
        scrollView.addSubview(content)
        scrollView.zoomView = content
        scrollView.pageContentFrame = { CGRect(x: 100, y: 0, width: 200, height: 800) }
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        window.layoutIfNeeded()
        scrollView.applyPageSizing(.fill, resetZoom: true)
        let restingOffset = scrollView.contentOffset
        let restingInsets = scrollView.contentInset
        let restingContentSize = scrollView.contentSize
        #expect(scrollView.bounces)
        #expect(scrollView.alwaysBounceVertical)
        #expect(!scrollView.alwaysBounceHorizontal)
        #expect(!scrollView.bouncesZoom)

        // A real UIScrollView return animation, without mocked gesture phases.
        // Include x drift to reproduce the old full-offset correction that
        // stopped UIKit's vertical animation while correcting only the x axis.
        scrollView.setContentOffset(CGPoint(x: restingOffset.x + 20, y: restingOffset.y - 80), animated: false)
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()
        #expect(scrollView.contentOffset.y == restingOffset.y - 80)
        scrollView.setContentOffset(restingOffset, animated: true)
        var observedIntermediateOffset = false
        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 20_000_000)
            scrollView.setNeedsLayout()
            scrollView.layoutIfNeeded()
            let y = scrollView.contentOffset.y
            observedIntermediateOffset = observedIntermediateOffset || (y > restingOffset.y - 79 && y < restingOffset.y - 1)
            #expect(scrollView.contentInset == restingInsets)
            #expect(scrollView.contentSize == restingContentSize)
        }
        #expect(observedIntermediateOffset)
        #expect(abs(scrollView.contentOffset.y - restingOffset.y) < 1)
        #expect(abs(scrollView.contentOffset.x - restingOffset.x) < 1)
    }

    @Test("Unfolding during a bounce preserves the legal reading position")
    func bounceDoesNotChangeReadingPosition() {
        let scrollView = ZoomableScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let content = UIView(frame: scrollView.bounds)
        scrollView.addSubview(content)
        scrollView.zoomView = content
        scrollView.pageContentFrame = { CGRect(x: 100, y: 0, width: 200, height: 800) }
        scrollView.applyPageSizing(.fill, resetZoom: true)
        scrollView.setContentOffset(CGPoint(x: 200, y: 860), animated: false)
        #expect(scrollView.contentOffset.y == 860)

        scrollView.frame.size = CGSize(width: 800, height: 800)
        content.bounds.size = CGSize(width: 800, height: 800)
        scrollView.pageContentFrame = { CGRect(x: 300, y: 0, width: 200, height: 800) }
        scrollView.updatePageSizing()
        let artwork = content.convert(CGRect(x: 300, y: 0, width: 200, height: 800), to: scrollView)
        #expect(abs((scrollView.contentOffset.y - artwork.minY) / artwork.height - 0.5) < 0.001)
        #expect(abs(scrollView.contentOffset.x - artwork.minX) < 0.001)
    }

    @Test("Unfolding preserves the image position at the top of the viewport")
    func resizedViewport() {
        let (scrollView, content) = makeScrollView(pageFrame: CGRect(x: 100, y: 0, width: 200, height: 800))
        scrollView.applyPageSizing(.fill, resetZoom: true)
        scrollView.setContentOffset(CGPoint(x: 200, y: 400), animated: false)
        scrollView.frame.size = CGSize(width: 800, height: 800)
        content.bounds.size = CGSize(width: 800, height: 800)
        scrollView.pageContentFrame = { CGRect(x: 300, y: 0, width: 200, height: 800) }
        scrollView.updatePageSizing()
        let artwork = content.convert(CGRect(x: 300, y: 0, width: 200, height: 800), to: scrollView)

        #expect(scrollView.baselineZoomScale == 4)
        #expect(scrollView.zoomScale == 4)
        #expect(abs((scrollView.contentOffset.y - artwork.minY) / artwork.height - 0.25) < 0.001)
        #expect(scrollView.zoomView === content)
    }

    @Test("Width sizing waits for delayed artwork before setting its scale and top position")
    func delayedArtwork() {
        let (scrollView, content) = makeScrollView(pageFrame: .zero)
        scrollView.applyPageSizing(.fill, resetZoom: true)
        #expect(scrollView.zoomScale == 1)
        let frame = CGRect(x: 100, y: 0, width: 200, height: 800)
        scrollView.pageContentFrame = { frame }
        scrollView.updatePageSizing()
        let artwork = content.convert(frame, to: scrollView)

        #expect(scrollView.zoomScale == 2)
        #expect(scrollView.contentOffset == CGPoint(x: artwork.minX, y: artwork.minY))
    }

    @Test("Loaded page artwork stays full-width and top-aligned after a real Auto Layout resize")
    func loadedControllerResize() async throws {
        let store = ReaderTemporaryPageStore()
        let key = AppSettings.reader.pageSizing.key
        let previous = UserDefaults.standard.object(forKey: key)
        AppSettings.reader.pageSizing.set(.fill)
        do {
            let delegate = LoadedSizingReaderDelegate()
            let controller = ReaderPageViewController(type: .page, delegate: delegate, temporaryPageStore: store)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 466, height: 678))
            window.rootViewController = controller
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
                UserDefaults.standard.set(previous, forKey: key)
                NotificationCenter.default.post(name: .init(key), object: nil)
            }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 1000), format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 300, height: 1000))
            }
            controller.setPage(Page(sourceId: "test", chapterId: "resize", image: image), skipProcessing: true)
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
            let zoomView = try #require(controller.zoomView)
            try assertLoadedArtwork(controller: controller, zoomView: zoomView)

            window.frame.size = CGSize(width: 951, height: 669)
            window.setNeedsLayout()
            window.layoutIfNeeded()
            // Let normal child layout and its queued sizing notification settle;
            // do not force another recursive ancestor layout to mask the order.
            try await Task.sleep(nanoseconds: 100_000_000)
            try assertLoadedArtwork(controller: controller, zoomView: zoomView)
            await store.removeAll()
        } catch {
            UserDefaults.standard.set(previous, forKey: key)
            NotificationCenter.default.post(name: .init(key), object: nil)
            await store.removeAll()
            throw error
        }
    }

    private func assertLoadedArtwork(controller: ReaderPageViewController, zoomView: ZoomableScrollView) throws {
        let pageView = try #require(controller.pageView)
        let image = try #require(pageView.imageView.image)
        let frame = ReaderPageSizingGeometry.aspectFitFrame(imageSize: image.size, in: pageView.imageView.bounds)
        let artwork = pageView.imageView.convert(frame, to: zoomView)
        let pixel = 1 / max(1, zoomView.traitCollection.displayScale)
        #expect(abs(artwork.width - zoomView.bounds.width) <= pixel)
        #expect(abs(artwork.minX - zoomView.contentOffset.x) <= pixel)
        #expect(abs(artwork.minY - zoomView.contentOffset.y) <= pixel)
    }

    @Test("Switching from width mode to Fit restores pinch and double tap")
    func fitRestoresZoom() {
        let (scrollView, _) = makeScrollView(pageFrame: CGRect(x: 100, y: 0, width: 200, height: 800))
        scrollView.applyPageSizing(.fill, resetZoom: true)
        scrollView.applyPageSizing(.fit, resetZoom: true)
        #expect(scrollView.zoomScale == 1)
        #expect(scrollView.contentInset == .zero)
        #expect(scrollView.pinchGestureRecognizer?.isEnabled == true)
        #expect(scrollView.doubleTapEnabled)
        scrollView.zoom(to: CGPoint(x: 200, y: 400), animated: false)
        #expect(scrollView.zoomScale == 2)
        scrollView.doubleTapEnabled = false
        #expect(!scrollView.doubleTapEnabled)
    }

    @Test("Spread Fill uses the shared spread rather than zooming its pages independently")
    func spreadBaseline() {
        let scrollView = ZoomableScrollView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let spread = UIView(frame: CGRect(x: 0, y: 0, width: 800, height: 800))
        scrollView.addSubview(spread)
        scrollView.zoomView = spread
        scrollView.pageContentFrame = { spread.bounds }
        scrollView.applyPageSizing(.fill, resetZoom: true)

        #expect(scrollView.baselineZoomScale == 1.25)
        #expect(scrollView.zoomScale == 1.25)
        #expect(scrollView.zoomView === spread)
    }

    @Test("Loaded Fill Width pages release their individual zoom before entering a spread")
    func loadedSinglePagesEnterSpread() async throws {
        let store = ReaderTemporaryPageStore()
        let key = AppSettings.reader.pageSizing.key
        let previous = UserDefaults.standard.object(forKey: key)
        AppSettings.reader.pageSizing.set(.fill)
        defer {
            UserDefaults.standard.set(previous, forKey: key)
            NotificationCenter.default.post(name: .init(key), object: nil)
        }
        do {
            let delegate = LoadedSizingReaderDelegate()
            let first = ReaderPageViewController(type: .page, delegate: delegate, temporaryPageStore: store)
            let second = ReaderPageViewController(type: .page, delegate: delegate, temporaryPageStore: store)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
            window.rootViewController = first
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            second.loadViewIfNeeded()
            second.view.frame = window.bounds
            second.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 1200), format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 300, height: 1200))
            }
            first.setPage(Page(sourceId: "test", chapterId: "single-to-spread-first", image: image), skipProcessing: true)
            second.setPage(Page(sourceId: "test", chapterId: "single-to-spread-second", image: image), skipProcessing: true)
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
            let firstZoom = try #require(first.zoomView)
            let secondZoom = try #require(second.zoomView)
            let firstPage = try #require(first.pageView)
            let secondPage = try #require(second.pageView)
            let firstImage = try #require(firstPage.imageView.image)
            let secondImage = try #require(secondPage.imageView.image)
            for zoom in [firstZoom, secondZoom] {
                #expect(zoom.minimumZoomScale > 1)
                #expect(zoom.minimumZoomScale == zoom.maximumZoomScale)
                #expect(zoom.zoomScale == zoom.minimumZoomScale)
            }
            #expect(!firstPage.transform.isIdentity)
            #expect(!secondPage.transform.isIdentity)

            let spread = ReaderDoublePageViewController(firstPage: first, secondPage: second, direction: .ltr)
            spread.loadViewIfNeeded()
            spread.view.frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
            spread.viewWillAppear(false)
            let stack = try #require(spread.zoomView.zoomView)
            for (zoom, page) in [(firstZoom, firstPage), (secondZoom, secondPage)] {
                #expect(zoom.zoomScale == 1)
                #expect(page.transform.isIdentity)
                #expect(page.isDescendant(of: stack))
            }
            #expect(firstPage.imageView.image === firstImage)
            #expect(secondPage.imageView.image === secondImage)

            // Returning to the single-page reader restores its width lock and
            // artwork alignment after the page is attached to its original view.
            spread.viewDidDisappear(false)
            first.view.setNeedsLayout()
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
            #expect(firstPage.superview === firstZoom)
            #expect(firstZoom.minimumZoomScale == firstZoom.baselineZoomScale)
            #expect(firstZoom.maximumZoomScale == firstZoom.baselineZoomScale)
            #expect(firstZoom.baselineZoomScale > 1)
            try assertLoadedArtwork(controller: first, zoomView: firstZoom)
            await store.removeAll()
        } catch {
            await store.removeAll()
            throw error
        }
    }

    @Test("Double-page sizing measures drawn artwork rather than stack or image-view letterboxes")
    func renderedSpreadBounds() async throws {
        let temporaryStore = ReaderTemporaryPageStore()
        do {
            let first = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: temporaryStore)
            let second = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: temporaryStore)
            let controller = ReaderDoublePageViewController(firstPage: first, secondPage: second, direction: .ltr)
            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
            controller.viewWillAppear(false)
            controller.view.layoutIfNeeded()
            let stack = try #require(controller.zoomView.zoomView)
            let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100)).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
            }
            // Measure the real controller's content-frame provider with fixed
            // post-layout geometry. This isolates artwork measurement from the
            // reader's separate image-constraint and spread-pairing behavior.
            stack.bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
            for (index, page) in [first, second].enumerated() {
                let pageView = try #require(page.pageView)
                let imageView = pageView.imageView
                pageView.frame = CGRect(x: CGFloat(index) * 200, y: 0, width: 200, height: 800)
                imageView.image = image
                imageView.frame = CGRect(x: 0, y: 250, width: 200, height: 300)
            }
            let artwork = try #require(controller.zoomView.pageContentFrame?())
            let firstImageView = try #require(first.pageView?.imageView)

            #expect(artwork == CGRect(x: 0, y: 350, width: 400, height: 100))
            #expect(artwork.height < stack.bounds.height)
            #expect(artwork.height < firstImageView.bounds.height)
            await temporaryStore.removeAll()
        } catch {
            await temporaryStore.removeAll()
            throw error
        }
    }

    @Test("Paged artwork keeps full bounds while asymmetric safe areas remain available for controls")
    func safeViewport() async throws {
        let temporaryStore = ReaderTemporaryPageStore()
        do {
            let controller = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: temporaryStore)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1100, height: 900))
            window.rootViewController = controller
            controller.additionalSafeAreaInsets = UIEdgeInsets(top: 20, left: 80, bottom: 30, right: 16)
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            let zoomView = try #require(controller.zoomView)

            #expect(zoomView.frame == controller.view.bounds)
            #expect(zoomView.frame != controller.view.safeAreaLayoutGuide.layoutFrame)
            #expect(controller.view.safeAreaInsets.left >= 80)
            #expect(controller.view.safeAreaInsets.right >= 16)
            await temporaryStore.removeAll()
        } catch {
            await temporaryStore.removeAll()
            throw error
        }
    }

    private func makeScrollView(pageFrame: CGRect) -> (ZoomableScrollView, UIView) {
        let scrollView = ZoomableScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let content = UIView(frame: scrollView.bounds)
        scrollView.addSubview(content)
        scrollView.zoomView = content
        scrollView.pageContentFrame = { pageFrame }
        return (scrollView, content)
    }
}

private final class LoadedSizingReaderDelegate: ReaderHoldingDelegate {
    var barsHidden = true
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
