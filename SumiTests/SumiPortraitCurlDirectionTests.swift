@testable import Sumi
import Testing
import UIKit

@MainActor
struct SumiPortraitCurlDirectionTests {
    private let bounds = CGRect(x: 0, y: 0, width: 360, height: 600)

    @Test("A short reverse pull immediately brings the previous sheet into the viewport")
    func previousLeafRespondsImmediately() {
        let width: CGFloat = 360
        for travel: CGFloat in [0.02, 0.05, 0.1, 0.2] {
            let sheet = (0...200).map {
                SumiPageCurlGeometry.singlePageSample(at: CGFloat($0) / 200,
                    progress: 1 - travel, width: width)
            }
            #expect((sheet.map(\.x).max() ?? 0) > width * travel * 0.6,
                    "The visible curl must follow the first pull rather than waiting half a turn")
            #expect(sheet.contains { $0.angle > 0 && $0.angle < .pi })
            #expect(sheet.first?.x == 0 && sheet.first?.elevation == 0)
        }
    }

    @Test("A moving portrait crease preserves paper length and a continuous surface")
    func travellingCreaseIsContinuous() {
        let width: CGFloat = 360
        for progress: CGFloat in [0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99] {
            var previous = SumiPageCurlGeometry.singlePageSample(at: 0, progress: progress, width: width)
            var length: CGFloat = 0
            for step in 1...5000 {
                let next = SumiPageCurlGeometry.singlePageSample(at: CGFloat(step) / 5000,
                    progress: progress, width: width)
                let segment = hypot(next.x - previous.x, next.elevation - previous.elevation)
                #expect(segment <= width / 5000 + 0.000001)
                length += segment
                previous = next
            }
            #expect(abs(length - width) < 0.01)
        }
    }

    @Test("Going back returns the previous portrait leaf along the exact forward path")
    func reverseRetracesTheSameLeaf() throws {
        let previous = printImage(left: .red, right: .green)
        let current = printImage(left: .blue, right: .blue)
        let forward = SumiPageCurlView(frame: bounds, oldImages: [previous],
                                      newImages: [current], rightToLeft: true)
        let backward = SumiPageCurlView(frame: bounds, oldImages: [current],
                                       newImages: [previous], rightToLeft: false)
        let forwardStrips = try #require(named("sumi.reader.moving-paper", in: forward).sublayers)
        let backwardStrips = try #require(named("sumi.reader.moving-paper", in: backward).sublayers)
        #expect(forwardStrips.count == backwardStrips.count)
        for progress: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
            forward.update(progress: progress)
            backward.update(progress: 1 - progress)
            for (outgoing, incoming) in zip(forwardStrips, backwardStrips) {
                #expect(CATransform3DEqualToTransform(outgoing.transform, incoming.transform),
                        "Reverse must return the same sheet instead of reflecting its binding")
                #expect(outgoing.isHidden == incoming.isHidden)
                #expect(abs(outgoing.zPosition - incoming.zPosition) < 0.0001)
            }
            let forwardContact = try named("sumi.reader.binding-contact-shadow", in: forward)
            let backwardContact = try named("sumi.reader.binding-contact-shadow", in: backward)
            #expect(try #require(forwardContact.shadowPath).boundingBoxOfPath.midX == 0)
            #expect(try #require(backwardContact.shadowPath).boundingBoxOfPath.midX == 0,
                    "The portrait binding must stay on the left when reversing")
        }
    }

    @Test("A backward portrait turn moves the previous print and keeps the current print underneath")
    func previousArtworkReturnsUnmirrored() throws {
        let previous = printImage(left: .red, right: .green)
        let current = printImage(left: .blue, right: .blue)
        let backward = SumiPageCurlView(frame: bounds, oldImages: [current],
                                       newImages: [previous], rightToLeft: false)
        let paper = try named("sumi.reader.moving-paper", in: backward)
        let front = try #require(paper.sublayers?.first)
        let underneath = try named("sumi.reader.revealed-paper", in: backward)
        let left = try pixel(in: front, fraction: 0.25)
        let right = try pixel(in: front, fraction: 0.75)
        #expect(left[0] > 245 && left[1] < 10 && left[2] < 10)
        #expect(right[1] > 245 && right[0] < 10 && right[2] < 10,
                "The previous page must return with readable, unmirrored artwork")
        for progress: CGFloat in [0, 0.35, 0.7, 1, 0.7, 0.35, 0] {
            backward.update(progress: progress)
            let under = try pixel(in: underneath, fraction: 0.5)
            #expect(under[2] > 245 && under[0] < 10 && under[1] < 10,
                    "The current page stays still beneath the incoming previous leaf, including cancellation")
            #expect(underneath.frame == bounds)
            #expect(CATransform3DIsIdentity(underneath.transform))
        }
    }

    @Test("A backward portrait leaf starts outside the left edge and finishes flat over the viewport")
    func exactReverseEndpoints() throws {
        let backward = SumiPageCurlView(frame: bounds,
            oldImages: [printImage(left: .blue, right: .blue)],
            newImages: [printImage(left: .red, right: .red)], rightToLeft: false)
        let layers = try #require(named("sumi.reader.moving-paper", in: backward).sublayers)
        let fronts = stride(from: 0, to: layers.count, by: 3).map { layers[$0] }
        #expect(!fronts.isEmpty)
        for progress: CGFloat in [0, 1, 0] {
            backward.update(progress: progress)
            let positions = fronts.flatMap { [projectedX(0, using: $0.transform), projectedX(1, using: $0.transform)] }
            let minimum = try #require(positions.min())
            let maximum = try #require(positions.max())
            if progress == 0 {
                #expect(abs(minimum + bounds.width) < 0.001)
                #expect(abs(maximum) < 0.001,
                        "The previous sheet starts offscreen on the left; current artwork is not peeled away")
                #expect(fronts.allSatisfy { $0.isHidden })
            } else {
                #expect(abs(minimum) < 0.001)
                #expect(abs(maximum - bounds.width) < 0.001)
                #expect(fronts.allSatisfy { !$0.isHidden })
            }
            #expect(try named("sumi.reader.cast-shadow", in: backward).shadowOpacity < 0.0001)
            #expect(try named("sumi.reader.binding-contact-shadow", in: backward).shadowOpacity < 0.0001)
        }
    }

    private func named(_ name: String, in view: UIView) throws -> CALayer {
        try #require(view.layer.sublayers?.first { $0.name == name })
    }

    private func projectedX(_ x: CGFloat, using transform: CATransform3D) -> CGFloat {
        (transform.m11 * x + transform.m41) / (transform.m14 * x + transform.m44)
    }

    private func printImage(left: UIColor, right: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            left.setFill()
            context.fill(bounds)
            right.setFill()
            context.fill(CGRect(x: bounds.midX, y: 0, width: bounds.width / 2, height: bounds.height))
        }
    }

    private func pixel(in layer: CALayer, fraction: CGFloat) throws -> [UInt8] {
        let contents = try #require(layer.contents)
        #expect(CFGetTypeID(contents as CFTypeRef) == CGImage.typeID)
        let image = contents as! CGImage
        let crop = try #require(image.cropping(to: CGRect(x: CGFloat(image.width) * fraction,
            y: CGFloat(image.height) / 2, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }
}
