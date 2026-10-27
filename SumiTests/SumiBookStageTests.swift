@testable import Sumi
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiBookStageTests {
    @Test("The unlit cover stage uses compositor image layers, not a Metal drawable")
    func nativeImageLayers() throws {
        let cover = image(.red)
        let stage = try SumiBookStageView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700),
            cover: cover, spread: image(.blue), paired: true)
        #expect(String(describing: type(of: stage.layer)) != "CAMetalLayer")
        #expect(stage.accessibilityIdentifier == "Sumi.Book.OpeningStage")
        let source = CGRect(x: 300, y: 180, width: 204, height: 300)
        #expect(stage.draw(progress: 0, source: source, deltaTime: 1 / 60))
        #expect(stage.containsBook(at: CGPoint(x: source.midX, y: source.midY)))
        #expect(!stage.containsBook(at: CGPoint(x: 20, y: 20)))
        #expect(stage.completedProgress == 0)
        #expect(stage.completedSourceFrame == source)
        #expect(stage.layer.sublayers?.count == 2, "One printed page and one hinged cover are sufficient")
    }

    @Test("Opening and reversed cancellation preserve the exact measured cover and viewport endpoints")
    func reversibleGeometry() throws {
        let source = CGRect(x: 200, y: 130, width: 170, height: 250)
        for paired in [true, false] {
            let stage = try SumiBookStageView(frame: CGRect(x: 0, y: 0, width: 900, height: 600),
                cover: image(.red), spread: image(.blue), paired: paired)
            for progress: CGFloat in [0, 0.25, 0.6, 1, 0.6, 0.25, 0] {
                #expect(stage.draw(progress: progress, source: source, deltaTime: 1 / 120))
                #expect(stage.completedProgress == progress)
                #expect(stage.completedSourceFrame == source)
                if progress == 1 {
                    #expect(stage.containsBook(at: CGPoint(x: 1, y: 300)))
                    #expect(stage.containsBook(at: CGPoint(x: 899, y: 300)))
                }
            }
            let hinge = try #require(stage.layer.sublayers?.last)
            #expect(abs(hinge.position.x - source.minX) < 0.001)
            #expect(abs(hinge.bounds.width - source.width) < 0.001)
            #expect(abs(hinge.bounds.height - source.height) < 0.001)
            #expect(CATransform3DIsIdentity(hinge.transform))
            #expect(!stage.containsBook(at: CGPoint(x: source.maxX + 1, y: source.midY)))
        }
    }

    @Test("The UIKit opening keeps original cover brightness and hands off both correctly ordered page prints")
    func compositorPrints() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let cover = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 120), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
            UIColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1).setFill()
            context.fill(CGRect(x: 80, y: 0, width: 80, height: 120))
            UIColor.green.setFill()
            context.fill(CGRect(x: 160, y: 0, width: 80, height: 120))
        }
        let spread = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 200, y: 0, width: 200, height: 300))
        }
        let stage = try SumiBookStageView(frame: CGRect(x: 0, y: 0, width: 400, height: 300),
            cover: cover, spread: spread, paired: true)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .alert + 2
        let host = UIViewController()
        host.view.backgroundColor = .black
        window.rootViewController = host
        host.view.addSubview(stage)
        window.makeKeyAndVisible()
        defer {
            let wasKey = window.isKeyWindow
            window.isHidden = true
            window.rootViewController = nil
            if wasKey { previousKeyWindow?.makeKey() }
        }
        let source = CGRect(x: 180, y: 80, width: 80, height: 120)
        _ = stage.draw(progress: 0, source: source, deltaTime: 1 / 60)
        window.layoutIfNeeded()
        CATransaction.flush()
        #expect(await SumiReaderFrameFence.wait())
        let closed = try stagePixel(stage, at: CGPoint(x: source.midX, y: source.midY))
        for (actual, expected) in zip(closed.prefix(3), [64, 128, 191]) {
            #expect(abs(Int(actual) - expected) <= 2, "Opening must preserve original print color: \(closed)")
        }
        let croppedEdge = try stagePixel(stage, at: CGPoint(x: source.minX + 4, y: source.midY))
        for (actual, expected) in zip(croppedEdge.prefix(3), [64, 128, 191]) {
            #expect(abs(Int(actual) - expected) <= 2,
                    "A wide cover must retain its centered crop on opening instead of stretching the side panels: \(croppedEdge)")
        }
        _ = stage.draw(progress: 1, source: source, deltaTime: 1 / 60)
        CATransaction.flush()
        #expect(await SumiReaderFrameFence.wait())
        let left = try stagePixel(stage, at: CGPoint(x: 100, y: 150))
        let right = try stagePixel(stage, at: CGPoint(x: 300, y: 150))
        #expect(left[0] > 245 && left[2] < 10, "Left page print must remain on the left: \(left)")
        #expect(right[2] > 245 && right[0] < 10, "Right page print must remain on the right: \(right)")
    }

    @Test("Canceling an opening keeps the rendered paper in place and closes directly at its source")
    func partialOpeningReturnUsesCapturedPaper() throws {
        let viewport = CGRect(x: 0, y: 0, width: 900, height: 600)
        let hovering = CGRect(x: 300, y: 120, width: 204, height: 300)
        let origin = CGRect(x: 36, y: 44, width: 102, height: 150)
        for paired in [false, true] {
            let stage = try SumiBookStageView(frame: viewport, cover: image(.red), spread: image(.blue), paired: paired)
            let visibleOpenness: CGFloat = 0.6
            #expect(stage.draw(progress: visibleOpenness, source: hovering, deltaTime: 1 / 60))
            let hinge = try #require(stage.layer.sublayers?.last)
            let previousPosition = hinge.position
            let previousBounds = hinge.bounds
            let previousTransform = hinge.transform
            let captured = SumiBookMotion.paperFrame(source: hovering, destination: viewport,
                                                     paired: paired, progress: visibleOpenness)
            let start = SumiBookReturnPose(progress: 1, origin: origin, initialOpenness: visibleOpenness)
            #expect(stage.draw(progress: start.openness, source: origin,
                paperFrame: start.paperFrame(in: viewport, paired: paired, startingAt: captured), deltaTime: 1 / 60))
            #expect(abs(hinge.position.x - previousPosition.x) < 0.000001)
            #expect(abs(hinge.position.y - previousPosition.y) < 0.000001)
            #expect(abs(hinge.bounds.width - previousBounds.width) < 0.000001)
            #expect(abs(hinge.bounds.height - previousBounds.height) < 0.000001)
            #expect(CATransform3DEqualToTransform(hinge.transform, previousTransform))

            let returned = SumiBookReturnPose(progress: 0, origin: origin, initialOpenness: visibleOpenness)
            #expect(stage.draw(progress: returned.openness, source: origin,
                paperFrame: returned.paperFrame(in: viewport, paired: paired, startingAt: captured), deltaTime: 1 / 60))
            #expect(abs(hinge.position.x - origin.minX) < 0.000001)
            #expect(abs(hinge.position.y - origin.midY) < 0.000001)
            #expect(abs(hinge.bounds.width - origin.width) < 0.000001)
            #expect(abs(hinge.bounds.height - origin.height) < 0.000001)
            #expect(CATransform3DIsIdentity(hinge.transform))
            #expect(stage.completedSourceFrame == origin)
        }
    }

    private func stagePixel(_ stage: UIView, at point: CGPoint) throws -> [UInt8] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        // CALayer.render(in:) flattens CATransformLayer and ignores its 3D
        // culling/transform. Inspect the real window compositor instead.
        var captured = false
        let raster = UIGraphicsImageRenderer(size: stage.bounds.size, format: format).image { _ in
            captured = stage.drawHierarchy(in: stage.bounds, afterScreenUpdates: true)
        }
        #expect(captured, "The test must capture the rendered onscreen stage")
        let cg = try #require(raster.cgImage)
        let crop = try #require(cg.cropping(to: CGRect(x: point.x, y: point.y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }

    private func image(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
    }
}
