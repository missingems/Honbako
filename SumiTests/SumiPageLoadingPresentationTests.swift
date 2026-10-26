@testable import Sumi
import AidokuRunner
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiPageLoadingPresentationTests {
    @Test("A late image fades over paper, while an already prepared image stays fully visible")
    func lateImageRevealAndCancellation() async throws {
        let scene = try activeScene()
        let host = UIViewController()
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.isHidden = false
        let store = ReaderTemporaryPageStore()
        let page = ReaderPageView(temporaryPageStore: store)
        page.frame = host.view.bounds
        host.view.addSubview(page)
        defer { window.isHidden = true; window.rootViewController = nil; Task { await store.removeAll() } }

        let placeholder = try #require(page.subviews.first { $0.accessibilityIdentifier == "Sumi.Reader.Page.Loading" })
        #expect(!placeholder.isHidden)
        page.setPageImage(image(.red))
        #expect(!page.sumiIsImageReady, "Opening readiness must wait for the actual image reveal")
        try await wait { page.sumiIsImageReady }
        #expect(placeholder.isHidden)
        let currentImage = try #require(page.imageView.image)
        page.setPageImage(currentImage)
        #expect(page.sumiIsImageReady, "Relayout or an existing print must not flash or restart a fade")

        page.setPageImage(nil)
        page.setPageImage(image(.blue))
        #expect(!page.sumiIsImageReady)
        page.setPageImage(nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(page.imageView.image == nil)
        #expect(!placeholder.isHidden, "A canceled reveal must not hide the new loading state")

        page.isHidden = true
        page.setPageImage(currentImage)
        #expect(page.imageView.alpha == 1, "An offscreen print must not restart its image reveal")
        // Edge colors are prepared off-main too. A preloaded page is ready
        // after both its bitmap and matching margins have finished preparing.
        try await wait { page.sumiIsImageReady }
        #expect(page.sumiIsImageReady, "An offscreen preloaded image is fully ready before its turn")
    }

    @Test("Loading during a curl fades at the handoff; a prepared target never fades again")
    func curlLoadingHandoff() async throws {
        for late in [false, true] {
            let pager = SumiPageCurlViewController(readingMode: .rtl)
            let window = UIWindow(windowScene: try activeScene())
            window.frame = window.windowScene!.coordinateSpace.bounds
            window.rootViewController = pager
            window.isHidden = false
            let store = ReaderTemporaryPageStore()
            defer { window.isHidden = true; window.rootViewController = nil; Task { await store.removeAll() } }
            let first = UIViewController()
            first.view.backgroundColor = .red
            let target = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: store)
            let artwork = image(.blue)
            if !late { target.pageView?.setPageImage(artwork) }
            pager.setViewControllers([first], direction: .forward, animated: false)
            var readyAtHandoff: Bool?
            pager.setViewControllers([target], direction: .reverse, animated: true) { completed in
                #expect(completed)
                readyAtHandoff = target.pageView?.sumiIsImageReady
            }
            let content = try #require(first.view.superview)
            #expect(content.subviews.first === target.view,
                    "Preparing the next print must stage it behind the visible current page")
            if late { target.pageView?.setPageImage(artwork) }
            try await wait { readyAtHandoff != nil }
            #expect(readyAtHandoff == !late)
            try await wait { target.pageView?.sumiIsImageReady == true }
            #expect(pager.viewControllers?.first === target)
        }
    }

    @Test("Returning to a detached hidden page captures its actual print before the reverse curl")
    func reusedPreviousPagePrintRemainsVisible() async throws {
        let pager = SumiPageCurlViewController(readingMode: .rtl)
        let window = UIWindow(windowScene: try activeScene())
        window.frame = window.windowScene!.coordinateSpace.bounds
        window.rootViewController = pager
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let previous = UIViewController()
        previous.view.backgroundColor = .red
        let current = UIViewController()
        current.view.backgroundColor = .blue
        pager.setViewControllers([previous], direction: .forward, animated: false)
        pager.setViewControllers([current], direction: .reverse, animated: true)
        try await wait { !pager.isTurning }
        #expect(pager.viewControllers?.first === current)
        #expect(previous.view.isHidden, "The regression requires the cached outgoing page to have been hidden")

        pager.setViewControllers([previous], direction: .forward, animated: true)
        let content = try #require(current.view.superview)
        let curl = try #require(content.subviews.compactMap { $0 as? SumiPageCurlView }.first)
        let moving = try #require(curl.layer.sublayers?.first { $0.name == "sumi.reader.moving-paper" })
        let front = try #require(moving.sublayers?.first)
        let print = try #require(front.contents) as! CGImage
        let crop = try #require(print.cropping(to: CGRect(x: print.width / 2, y: print.height / 2, width: 1, height: 1)))
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(data: bytes.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        #expect(rgba[0] > 245 && rgba[1] < 10 && rgba[2] < 10 && rgba[3] > 245,
                "The incoming previous sheet must contain opaque red artwork, not a transparent hidden-view snapshot: \(rgba)")
        #expect(content.subviews.first === previous.view, "Restoring print visibility must still stage behind current artwork")
        try await wait { !pager.isTurning }
        #expect(pager.viewControllers?.first === previous)
        #expect(!previous.view.isHidden)
    }

    @Test("Settling near a page prepares its neighbors and releases distant decoded pages")
    func boundedDecodedNeighborhood() async throws {
        let store = ReaderTemporaryPageStore()
        let reader = ReaderPagedViewController(source: nil,
            manga: .init(sourceKey: "sumi-loading-test", key: "preload", title: "Preload"), temporaryPageStore: store)
        let window = UIWindow(windowScene: try activeScene())
        window.frame = window.windowScene!.coordinateSpace.bounds
        window.rootViewController = reader
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; Task { await store.removeAll() } }
        let print = image(.white)
        reader.viewModel.sumiPageLoaderOverride = { chapter in
            (0..<30).map { .init(sourceId: "sumi-loading-test", chapterId: chapter.id, index: $0, image: print) }
        }
        reader.setChapter(.init(key: "preload"), startPage: 1)
        try await wait { reader.sumiReadyForOpening }
        try await wait { reader.pageViewControllers.filter { $0.pageView?.imageView.image != nil }.count >= 7 }
        #expect(reader.pageViewControllers[7].pageView?.imageView.image != nil,
                "Pages ahead must already be decoded before the next gesture")
        reader.move(toPage: 20, animated: false)
        try await wait { reader.sumiReadyForOpening }
        #expect(reader.pageViewControllers[1].pageView?.imageView.image == nil)
        let decoded = reader.pageViewControllers.filter { $0.pageView?.imageView.image != nil }.count
        #expect(decoded <= 10, "A long chapter must retain a bounded neighborhood, not every decoded page")
        reader.move(toPage: 1, animated: false)
        try await wait { reader.sumiReadyForOpening }
        #expect(reader.pageViewControllers[1].pageView?.imageView.image != nil,
                "Returning to an evicted page must load its original artwork again")
    }

    private func activeScene() throws -> UIWindowScene {
        try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
    }

    private func image(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        }
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(condition())
    }
}
