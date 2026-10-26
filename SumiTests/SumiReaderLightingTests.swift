@testable import Sumi
import Testing
import UIKit

@MainActor
struct SumiReaderLightingTests {
    @Test("Both settled paper shoulders receive equal, visible binding shade")
    func mirroredBindingShade() throws {
        let size = CGSize(width: 900, height: 650)
        let view = UIView(frame: CGRect(origin: .zero, size: size))
        view.backgroundColor = .white
        for (x, edge) in [(CGFloat(0), ReaderBookSpineView.BindingEdge.right), (450, .left)] {
            let leaf = UIView(frame: CGRect(x: x, y: 0, width: 450, height: 650))
            leaf.backgroundColor = .white
            let lighting = CALayer()
            leaf.layer.addSublayer(lighting)
            ReaderBookSpineView.updateBindingLighting(lighting, in: leaf.bounds, edge: edge)
            view.addSubview(leaf)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }
        let cg = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(origin: .zero, size: size))
        }
        func brightness(_ x: Int) -> Int { Int(bytes[(325 * cg.width + x) * 4]) }
        // Raster positions mirror around the half-pixel boundary between leaves.
        #expect(abs(brightness(434) - brightness(465)) <= 1)
        #expect(brightness(434) < 240 && brightness(465) < 240)
        #expect(brightness(80) > 252 && brightness(819) > 252)
    }

    @Test("Curl shadows land on either paper shoulder without changing the central cleft")
    func constantSpineMaterial() throws {
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 650)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 450, height: 650)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 450, height: 650))
        }
        let turn = SumiPageCurlView(frame: bounds, oldImages: [image, image], newImages: [image, image], rightToLeft: true)
        let spine = try #require(turn.subviews.compactMap { $0 as? ReaderBookSpineView }.first)
        let gutter = try #require(spine.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
        let originalColor = try #require(gutter.fillColor)
        for progress: CGFloat in [0, 0.001, 0.05, 0.25, 0.5, 0.75, 0.95, 0.999, 1] {
            turn.update(progress: progress)
            #expect(spine.alpha == 1 && !spine.isHidden)
            #expect(gutter.fillColor == originalColor)
            for layer in turn.layer.sublayers ?? [] where layer.name?.contains("shadow") == true {
                let receivingPaper = try #require(layer.mask as? CAShapeLayer)
                let path = try #require(receivingPaper.path)
                #expect(!path.contains(CGPoint(x: 450, y: 325)))
                #expect(path.contains(CGPoint(x: 435, y: 325)))
                #expect(path.contains(CGPoint(x: 465, y: 325)))
            }
        }
    }

    @Test("Diffuse cast shadows reach both sides as either leaf passes the binding")
    func twoSidedShadow() {
        for sign: CGFloat in [-1, 1] {
            var points: [CGPoint] = []
            for step in 0...56 {
                let sample = SumiPageCurlGeometry.sample(at: CGFloat(step) / 56, progress: 0.5, width: 450)
                for y: CGFloat in [0, 650] {
                    for light: CGFloat in [-1, 1] {
                        points.append(SumiPageCurlGeometry.castShadow(sample, y: y, hinge: 450, sign: sign, lightDirection: light))
                    }
                }
            }
            let footprint = SumiPageCurlGeometry.shadowFootprint(points)
            #expect(footprint.contains(CGPoint(x: 435, y: 325)))
            #expect(footprint.contains(CGPoint(x: 465, y: 325)))
        }
    }

    @Test("Page lighting eases gently from both flat endpoints")
    func gentleLightingEndpoints() {
        #expect(SumiPageCurlGeometry.lightingEnvelope(progress: 0) == 0)
        #expect(SumiPageCurlGeometry.lightingEnvelope(progress: 1) < 0.00001)
        #expect(SumiPageCurlGeometry.lightingEnvelope(progress: 0.001) < 0.00002)
        #expect(SumiPageCurlGeometry.lightingEnvelope(progress: 0.999) < 0.00002)
        #expect(SumiPageCurlGeometry.lightingEnvelope(progress: 0.5) == 1)
        for step in 0...100 {
            let p = CGFloat(step) / 100
            #expect(abs(SumiPageCurlGeometry.lightingEnvelope(progress: p)
                - SumiPageCurlGeometry.lightingEnvelope(progress: 1 - p)) < 0.00001)
        }
    }
}
