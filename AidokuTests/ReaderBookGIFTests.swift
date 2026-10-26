@testable import Aidoku
import Gifu
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

@MainActor
@Suite(.serialized)
struct ReaderBookGIFTests {
    @Test("Wide GIF leaves share one animation clock and stop on static replacement or clear")
    func sharedAnimationAndCleanup() async throws {
        let store = ReaderTemporaryPageStore()
        let canonical = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: store)
        canonical.loadViewIfNeeded()
        let page = try #require(canonical.pageView)
        let left = ReaderBookWideLeafViewController(canonicalController: canonical, side: .left)
        let right = ReaderBookWideLeafViewController(canonicalController: canonical, side: .right)
        let host = ReaderBookSpreadViewController(leaves: [left, right])
        let scene = try #require(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let priorKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            canonical.clearPage()
            window.isHidden = true
            window.rootViewController = nil
            priorKeyWindow?.makeKey()
        }
        #expect(left.view.window === window)
        #expect(right.view.window === window)
        page.onReferenceContentChanged = { [weak left, weak right] in
            left?.refreshImage()
            right?.refreshImage()
        }
        let data = try twoFrameWideGIF()
        let image = try #require(UIImage(data: data))
        page.setPageImage(image, gifData: data)
        window.layoutIfNeeded()
        #expect(page.gifData == data)
        #expect(left.imageView.animator === page.imageView.animator)
        #expect(right.imageView.animator === page.imageView.animator)
        #expect(left.imageView.frameCount == 2)
        #expect(right.imageView.frameCount == 2)
        #expect(left.imageView.isAnimatingGIF)
        #expect(right.imageView.isAnimatingGIF)
        for _ in 0..<50 {
            if left.imageView.activeFrame != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let initial = try #require(left.imageView.activeFrame)
        var firstDisplayedFrame: UIImage?
        for _ in 0..<50 {
            if let displayed = left.imageView.image, displayed !== image, displayed === right.imageView.image {
                firstDisplayedFrame = displayed
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let initiallyRendered = try #require(firstDisplayedFrame)
        var advanced = false
        var visiblyAdvanced = false
        for _ in 0..<50 {
            try await Task.sleep(nanoseconds: 20_000_000)
            let active = left.imageView.activeFrame
            #expect(active === right.imageView.activeFrame)
            advanced = advanced || (active != nil && active !== initial)
            visiblyAdvanced = visiblyAdvanced || (left.imageView.image !== initiallyRendered
                && left.imageView.image === right.imageView.image)
            if advanced && visiblyAdvanced { break }
        }
        #expect(advanced)
        #expect(visiblyAdvanced)

        let staticImage = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 60)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 60))
        }
        page.setPageImage(staticImage)
        #expect(page.gifData == nil)
        #expect(!page.imageView.isAnimatingGIF)
        #expect(page.imageView.frameCount == 0)
        #expect(left.imageView.animator == nil)
        #expect(right.imageView.animator == nil)
        #expect(left.imageView.image === staticImage)
        #expect(right.imageView.image === staticImage)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(left.imageView.image === staticImage)
        #expect(right.imageView.image === staticImage)

        page.setPageImage(image, gifData: data)
        #expect(left.imageView.animator === page.imageView.animator)
        #expect(right.imageView.animator === page.imageView.animator)
        canonical.clearPage()
        #expect(page.gifData == nil)
        #expect(!page.imageView.isAnimatingGIF)
        #expect(page.imageView.frameCount == 0)
        #expect(left.imageView.animator == nil)
        #expect(right.imageView.animator == nil)
        #expect(left.imageView.image == nil)
        #expect(right.imageView.image == nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(page.gifData == nil)
        #expect(!page.imageView.isAnimatingGIF)
        #expect(left.imageView.animator == nil)
        #expect(right.imageView.animator == nil)
        #expect(left.imageView.image == nil)
        #expect(right.imageView.image == nil)
        await store.removeAll()
    }

    private func twoFrameWideGIF() throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        for color in [UIColor.red, .blue] {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 60), format: format).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 120, height: 60))
            }
            let frame = try #require(image.cgImage)
            let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.08]] as CFDictionary
            CGImageDestinationAddImage(destination, frame, properties)
        }
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
