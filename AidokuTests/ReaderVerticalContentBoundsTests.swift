@testable import Aidoku
import AidokuRunner
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct ReaderVerticalContentBoundsTests {
    @Test("White edge detection retains a gutter and preserves faint isolated marks")
    func conservativeWhiteEdges() throws {
        let image = fixture()
        let bounds = ReaderVerticalContentBounds.detect(in: try #require(image.cgImage))
        #expect(abs(bounds.minY - 0.096) < 0.0001)
        #expect(abs(bounds.maxY - 0.854) < 0.0001)
        let faint = fixture(faintMark: true)
        let faintBounds = ReaderVerticalContentBounds.detect(in: try #require(faint.cgImage))
        #expect(abs(faintBounds.minY - 0.016) < 0.0001)
        #expect(faintBounds.maxY == bounds.maxY)
        let frame = bounds.frame(in: CGRect(x: 20, y: 40, width: 400, height: 1000))
        #expect(frame.minX == 20)
        #expect(frame.width == 400)
        #expect(abs(frame.minY - 136) < 0.0001)
        #expect(abs(frame.height - 758) < 0.0001)
    }

    @Test("Blank pages, colored paper, dark borders and large deliberate margins stay intact")
    func ambiguousEdgesStayIntact() throws {
        for background in [UIColor.white, UIColor(white: 0.96, alpha: 1), .black] {
            let image = fixture(background: background, drawContent: false)
            #expect(ReaderVerticalContentBounds.detect(in: try #require(image.cgImage)) == .fullImage)
        }
        let largeMargin = fixture(contentTop: 250)
        #expect(ReaderVerticalContentBounds.detect(in: try #require(largeMargin.cgImage)).minY == 0)
        let border = fixture(border: true)
        #expect(ReaderVerticalContentBounds.detect(in: try #require(border.cgImage)) == .fullImage)
    }

    @Test("Loaded Fill Width page trims scroll limits without changing its bitmap or Fit geometry")
    func loadedPagePresentationAndReset() async throws {
        try await withFillWidth { store, scene in
            let controller = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: store)
            let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
            let window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previousKeyWindow?.makeKey()
            }
            let image = fixture()
            controller.setPage(Page(sourceId: "margin-test", chapterId: "single", image: image), skipProcessing: true)
            let page = try #require(controller.pageView)
            let zoom = try #require(controller.zoomView)
            try await settle(window, until: { page.verticalContentBounds != .fullImage })
            zoom.updatePageSizing(resetZoom: true)
            #expect(page.imageView.image === image)
            let fullFrame = page.imageView.convert(
                ReaderPageSizingGeometry.aspectFitFrame(imageSize: image.size, in: page.imageView.bounds), to: page
            )
            let content = try #require(zoom.pageContentFrame?())
            #expect(content == page.verticalContentBounds.frame(in: fullFrame))
            #expect(content.width == fullFrame.width)
            #expect(content.height < fullFrame.height)
            let visibleContent = page.convert(content, to: zoom).offsetBy(dx: -zoom.contentOffset.x, dy: -zoom.contentOffset.y)
            #expect(abs(visibleContent.minY) < 0.5)
            #expect(abs(visibleContent.width - zoom.bounds.width) < 0.5)
            #expect(zoom.contentSize.height + zoom.adjustedContentInset.top + zoom.adjustedContentInset.bottom
                    < fullFrame.height * zoom.zoomScale)

            setSizing(.fit)
            window.layoutIfNeeded()
            #expect(zoom.pageContentFrame?() == fullFrame)
            #expect(page.imageView.image === image)
            setSizing(.fill)
            window.layoutIfNeeded()
            #expect(zoom.pageContentFrame?() == content)
            controller.clearPage()
            #expect(page.verticalContentBounds == .fullImage)
            try await Task.sleep(nanoseconds: 30_000_000)
            #expect(page.verticalContentBounds == .fullImage)
            #expect(page.imageView.image == nil)
        }
    }

    @Test("Both book halves use the same original-image vertical bounds and restore Fit")
    func wideLeavesShareBounds() async throws {
        try await withFillWidth { store, scene in
            let canonical = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: store)
            canonical.loadViewIfNeeded()
            let page = try #require(canonical.pageView)
            let left = ReaderBookWideLeafViewController(canonicalController: canonical, side: .left)
            let right = ReaderBookWideLeafViewController(canonicalController: canonical, side: .right)
            page.onReferenceContentChanged = { [weak left, weak right] in
                left?.refreshImage()
                right?.refreshImage()
            }
            let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
            let window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            window.rootViewController = ReaderBookSpreadViewController(leaves: [left, right])
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previousKeyWindow?.makeKey()
            }
            let image = fixture(size: CGSize(width: 1200, height: 1000))
            page.setPageImage(image)
            try await settle(window, until: { page.verticalContentBounds != .fullImage })
            let leftFrame = try #require(left.zoomView.pageContentFrame?())
            let rightFrame = try #require(right.zoomView.pageContentFrame?())
            #expect(leftFrame.minY == rightFrame.minY)
            #expect(leftFrame.height == rightFrame.height)
            #expect(left.imageView.image === image)
            #expect(right.imageView.image === image)
            let originalBounds = left.canonicalImageRect.union(right.canonicalImageRect)
            #expect(originalBounds == CGRect(origin: .zero, size: image.size))
            setSizing(.fit)
            window.layoutIfNeeded()
            let fullLeft = try #require(left.zoomView.pageContentFrame?())
            #expect(fullLeft.height > leftFrame.height)
            #expect(left.imageView.image === image)
            #expect(right.imageView.image === image)
        }
    }

    @Test("Animated and rotated images retain all source rows")
    func unsupportedImagesStayIntact() async throws {
        try await withFillWidth { store, _ in
            let page = ReaderPageView(temporaryPageStore: store)
            let still = fixture()
            let animated = try #require(UIImage.animatedImage(with: [still, still], duration: 1))
            let rotated = UIImage(cgImage: try #require(still.cgImage), scale: 1, orientation: .left)
            for image in [animated, rotated] {
                page.setPageImage(image)
                let frame = CGRect(x: 0, y: 0, width: 400, height: 1000)
                #expect(page.contentFrameForPageSizing(frame) == frame)
                try await Task.sleep(nanoseconds: 30_000_000)
                #expect(page.verticalContentBounds == .fullImage)
            }
        }
    }

    private func fixture(size: CGSize = CGSize(width: 400, height: 1000), background: UIColor = .white,
                         drawContent: Bool = true, contentTop: CGFloat = 100,
                         faintMark: Bool = false, border: Bool = false) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            if drawContent {
                UIColor.black.setFill()
                context.fill(CGRect(x: 40, y: contentTop, width: size.width - 80, height: 850 - contentTop))
            }
            if faintMark {
                UIColor(white: 245.0 / 255, alpha: 1).setFill()
                context.fill(CGRect(x: 12, y: 20, width: 1, height: 1))
            }
            if border {
                UIColor.black.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1, height: size.height))
            }
        }
    }

    private func settle(_ window: UIWindow, until condition: () -> Bool) async throws {
        for _ in 0..<100 {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            if condition() {
                try await Task.sleep(nanoseconds: 20_000_000)
                window.layoutIfNeeded()
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(condition())
    }

    private func setSizing(_ sizing: ReaderPageSizing) {
        AppSettings.reader.pageSizing.set(sizing)
        NotificationCenter.default.post(name: .init(AppSettings.reader.pageSizing.key), object: nil)
    }

    private func withFillWidth(_ body: (ReaderTemporaryPageStore, UIWindowScene) async throws -> Void) async throws {
        let previous = UserDefaults.standard.object(forKey: AppSettings.reader.pageSizing.key)
        defer {
            UserDefaults.standard.set(previous, forKey: AppSettings.reader.pageSizing.key)
            NotificationCenter.default.post(name: .init(AppSettings.reader.pageSizing.key), object: nil)
        }
        setSizing(.fill)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let store = ReaderTemporaryPageStore()
        do { try await body(store, scene) }
        catch { await store.removeAll(); throw error }
        await store.removeAll()
    }
}
