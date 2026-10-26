@testable import Sumi
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiPageEdgeColorsTests {
    private let red = SumiPageEdgeColors.Color(red: 255, green: 0, blue: 0)
    private let green = SumiPageEdgeColors.Color(red: 0, green: 255, blue: 0)
    private let blue = SumiPageEdgeColors.Color(red: 0, green: 0, blue: 255)
    private let black = SumiPageEdgeColors.Color(red: 0, green: 0, blue: 0)
    private let white = SumiPageEdgeColors.Color(red: 255, green: 255, blue: 255)

    @Test("Four different page borders retain four independent real colors")
    func independentEdges() throws {
        let image = borderImage()
        let bitmap = try #require(image.cgImage)
        let colors = try #require(SumiPageEdgeColors.sample(image: bitmap))
        #expect(colors.top == red)
        #expect(colors.leading == green)
        #expect(colors.trailing == blue)
        #expect(colors.bottom == black)
    }

    @Test("A little edge text cannot average white paper into gray")
    func dominantPaperIgnoresText() throws {
        let image = raster(size: CGSize(width: 100, height: 80)) { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
            UIColor.black.setFill(); context.fill(CGRect(x: 20, y: 0, width: 20, height: 2))
        }
        let bitmap = try #require(image.cgImage)
        let colors = try #require(SumiPageEdgeColors.sample(image: bitmap))
        #expect(colors.top == white)
        #expect(colors.leading == white)
        #expect(colors.trailing == white)
        #expect(colors.bottom == white)
    }

    @Test("Orientation maps the bitmap's colors to its displayed edges")
    func displayedOrientation() throws {
        let bitmap = try #require(borderImage().cgImage)
        let cases: [(UIImage.Orientation, SumiPageEdgeColors.Color, SumiPageEdgeColors.Color,
                     SumiPageEdgeColors.Color, SumiPageEdgeColors.Color)] = [
            (.up, red, green, blue, black), (.down, black, blue, green, red),
            (.left, blue, red, black, green), (.right, green, black, red, blue),
            (.upMirrored, red, blue, green, black), (.downMirrored, black, green, blue, red),
            (.leftMirrored, green, red, black, blue), (.rightMirrored, blue, black, red, green)
        ]
        for (orientation, top, leading, trailing, bottom) in cases {
            let colors = try #require(SumiPageEdgeColors.sample(image: bitmap, orientation: orientation))
            #expect(colors.top == top)
            #expect(colors.leading == leading)
            #expect(colors.trailing == trailing)
            #expect(colors.bottom == bottom)
        }
    }

    @Test("A clipped wide leaf samples its own top, bottom, and internal cut edge")
    func clippedHalves() throws {
        let bitmap = try #require(splitBorderImage().cgImage)
        let left = try #require(SumiPageEdgeColors.sample(image: bitmap,
            crop: CGRect(x: 0, y: 0, width: 0.5, height: 1)))
        let right = try #require(SumiPageEdgeColors.sample(image: bitmap,
            crop: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)))
        #expect(left.top == red && left.bottom == green)
        #expect(left.leading == white && left.trailing == black)
        #expect(right.top == blue)
        #expect(right.bottom == SumiPageEdgeColors.Color(red: 0, green: 255, blue: 255))
        #expect(right.leading == SumiPageEdgeColors.Color(red: 255, green: 255, blue: 0))
        #expect(right.trailing == SumiPageEdgeColors.Color(red: 255, green: 0, blue: 255))
    }

    @Test("Image identity and visible crop prevent another page or leaf from reusing its palette")
    func cacheIdentity() throws {
        let first = try #require(borderImage().cgImage)
        let second = try #require(raster(size: CGSize(width: 100, height: 80)) { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        }.cgImage)
        #expect(SumiPageEdgeColors.identity(image: first, orientation: .up, crop: CGRect(x: 0, y: 0, width: 1, height: 1))
                != SumiPageEdgeColors.identity(image: second, orientation: .up, crop: CGRect(x: 0, y: 0, width: 1, height: 1)))
        let one = try #require(SumiPageEdgeColors.sample(image: first))
        let two = try #require(SumiPageEdgeColors.sample(image: second))
        #expect(one.top == red && two.top == blue)
        #expect(SumiPageEdgeColors.sample(image: first) == one)
        #expect(SumiPageEdgeColors.sample(image: first, crop: .zero) == nil)
    }

    @Test("Fit margins occupy only the space adjacent to their matching edge")
    func marginGeometry() {
        let viewport = CGRect(x: 0, y: 0, width: 240, height: 340)
        let image = CGRect(x: 50, y: 60, width: 100, height: 200)
        let regions = SumiPageEdgeBackgroundView.regions(in: viewport, imageFrame: image)
        #expect(regions.top == CGRect(x: 0, y: 0, width: 240, height: 60))
        #expect(regions.leading == CGRect(x: 0, y: 60, width: 50, height: 200))
        #expect(regions.trailing == CGRect(x: 150, y: 60, width: 90, height: 200))
        #expect(regions.bottom == CGRect(x: 0, y: 260, width: 240, height: 80))
        for margin in [regions.top, regions.leading, regions.trailing, regions.bottom] {
            #expect(margin.intersection(image).isEmpty)
        }
        let clipped = SumiPageEdgeBackgroundView.regions(in: viewport,
            imageFrame: CGRect(x: -100, y: 30, width: 400, height: 280))
        #expect(clipped.leading.isEmpty && clipped.trailing.isEmpty)
        #expect(clipped.top.height == 30 && clipped.bottom.height == 30)
    }

    @Test("A real page keeps its bitmap and clears sampled margins with the loading placeholder")
    func pageLifecycle() async throws {
        let store = ReaderTemporaryPageStore()
        defer { Task { await store.removeAll() } }
        let page = ReaderPageView(temporaryPageStore: store)
        page.frame = CGRect(x: 0, y: 0, width: 200, height: 400)
        let image = borderImage()
        page.setPageImage(image)
        page.setNeedsLayout(); page.layoutIfNeeded()
        let background = try #require(page.subviews.compactMap { $0 as? SumiPageEdgeBackgroundView }.first)
        try await waitReady(background)
        background.layoutIfNeeded()
        #expect(background.colors?.top == red)
        #expect(background.colors?.bottom == black)
        #expect(page.imageView.image === image, "Matching a margin must never repaint or replace the page")
        #expect(page.sumiIsImageReady)
        let regions = SumiPageEdgeBackgroundView.regions(in: page.bounds, imageFrame: page.imageView.frame)
        #expect(regions.top.height > 0 && regions.bottom.height > 0)
        #expect(background.layer.sublayers?.first?.frame == regions.top)
        page.setPageImage(nil)
        #expect(background.colors == nil && background.alpha == 0)
        #expect(!page.sumiIsImageReady)
        for _ in 0..<5 { await Task.yield() }
        #expect(background.colors == nil, "An obsolete sample cannot recolor a loading placeholder")
    }

    @Test("Replacing and clearing an image cancels stale sampling before it can publish a palette")
    func staleSamplingIsDiscarded() async throws {
        let background = SumiPageEdgeBackgroundView(frame: CGRect(x: 0, y: 0, width: 200, height: 400))
        background.update(image: borderImage())
        background.update(image: splitBorderImage())
        background.update(image: nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(background.colors == nil && background.isReady)
        background.update(image: borderImage())
        try await waitReady(background)
        #expect(background.colors?.top == red && background.colors?.bottom == black)
    }

    @Test("Both live wide-image leaves fill their own letterbox without altering the canonical image")
    func wideLeafIntegration() async throws {
        let store = ReaderTemporaryPageStore()
        defer { Task { await store.removeAll() } }
        let controller = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: store)
        controller.loadViewIfNeeded()
        let image = splitBorderImage()
        controller.pageView?.setPageImage(image)
        for side in [ReaderBookWideLeafViewController.Side.left, .right] {
            let leaf = ReaderBookWideLeafViewController(canonicalController: controller, side: side)
            leaf.loadViewIfNeeded()
            leaf.view.frame = CGRect(x: 0, y: 0, width: 200, height: 400)
            leaf.refreshImage(); leaf.view.setNeedsLayout(); leaf.view.layoutIfNeeded()
            let background = try #require(leaf.view.subviews.compactMap { $0 as? SumiPageEdgeBackgroundView }.first)
            try await waitReady(background)
            background.layoutIfNeeded()
            #expect(background.colors?.top == (side == .left ? red : blue))
            #expect(leaf.imageView.image === image)
            #expect(leaf.sumiIsImageReady)
        }
        #expect(controller.pageView?.imageView.image === image)
    }

    @Test("Published margins are opaque before a same-color resolution replacement becomes ready")
    func equalPaletteReplacementFinishesReadiness() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let host = UIViewController()
        window.rootViewController = host
        let background = SumiPageEdgeBackgroundView(frame: CGRect(x: 0, y: 0, width: 200, height: 400))
        host.view.addSubview(background)
        window.makeKeyAndVisible()
        defer {
            let wasKey = window.isKeyWindow
            window.isHidden = true
            window.rootViewController = nil
            if wasKey { previousKeyWindow?.makeKey() }
        }
        let first = borderImage()
        let replacement = borderImage()
        background.update(image: first)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while background.colors == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(background.colors != nil)
        #expect(background.isReady && background.alpha == 1,
                "Published black edges must never blend with the white loading surface")
        background.update(image: replacement)
        try await waitReady(background)
        #expect(background.isReady)
        #expect(background.alpha == 1)
        #expect(background.colors?.top == red && background.colors?.bottom == black)
    }

    @Test("Black fit margins retain their exact pixels when the page viewport rotates")
    func blackMarginsRemainOpaqueAcrossRotation() async throws {
        let store = ReaderTemporaryPageStore()
        defer { Task { await store.removeAll() } }
        let page = ReaderPageView(temporaryPageStore: store)
        page.frame = CGRect(x: 0, y: 0, width: 240, height: 400)
        let image = raster(size: CGSize(width: 200, height: 300)) { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
            UIColor.white.setFill(); context.fill(CGRect(x: 20, y: 20, width: 160, height: 260))
        }
        page.setPageImage(image)
        let background = try #require(page.subviews.compactMap { $0 as? SumiPageEdgeBackgroundView }.first)
        try await waitReady(background)
        for viewport in [CGSize(width: 240, height: 400), CGSize(width: 500, height: 240),
                         CGSize(width: 240, height: 400)] {
            page.frame = CGRect(origin: .zero, size: viewport)
            page.setNeedsLayout(); page.layoutIfNeeded(); background.layoutIfNeeded()
            #expect(background.alpha == 1 && background.isReady)
            let colors = try #require(background.colors)
            #expect(colors.top == black && colors.leading == black && colors.trailing == black && colors.bottom == black)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1; format.opaque = true
            let capture = UIGraphicsImageRenderer(size: viewport, format: format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: viewport))
                page.layer.render(in: context.cgContext)
            }
            let bitmap = try #require(capture.cgImage)
            let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try #require(CGContext(data: nil, width: bitmap.width, height: bitmap.height,
                bitsPerComponent: 8, bytesPerRow: bitmap.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
            let pixels = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
            for point in [(1, 1), (bitmap.width - 2, 1), (1, bitmap.height - 2),
                          (bitmap.width - 2, bitmap.height - 2)] {
                let offset = point.1 * context.bytesPerRow + point.0 * 4
                #expect(pixels[offset] == 0 && pixels[offset + 1] == 0 && pixels[offset + 2] == 0,
                        "A captured fit margin must remain source black instead of a partial-opacity gray")
            }
        }
        #expect(page.imageView.image === image)
    }

    private func waitReady(_ background: SumiPageEdgeBackgroundView) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !background.isReady || background.colors == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(background.isReady && background.colors != nil)
    }

    private func borderImage() -> UIImage {
        raster(size: CGSize(width: 100, height: 80)) { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 1))
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 79, width: 100, height: 1))
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1, height: 80))
            UIColor.blue.setFill(); context.fill(CGRect(x: 99, y: 0, width: 1, height: 80))
        }
    }

    private func splitBorderImage() -> UIImage {
        raster(size: CGSize(width: 200, height: 100)) { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 1))
            UIColor.blue.setFill(); context.fill(CGRect(x: 100, y: 0, width: 100, height: 1))
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 99, width: 100, height: 1))
            UIColor.cyan.setFill(); context.fill(CGRect(x: 100, y: 99, width: 100, height: 1))
            UIColor.black.setFill(); context.fill(CGRect(x: 99, y: 0, width: 1, height: 100))
            UIColor.yellow.setFill(); context.fill(CGRect(x: 100, y: 0, width: 1, height: 100))
            UIColor.magenta.setFill(); context.fill(CGRect(x: 199, y: 0, width: 1, height: 100))
        }
    }

    private func raster(size: CGSize, draw: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image(actions: draw)
    }
}
