@testable import Sumi
import CoreGraphics
import MetalKit
import UIKit
import XCTest

/// Compare the real GPU paper with the neighbouring native print in one capture.
/// Distinct front/back charts also catch reversed face selection at flat endpoints.
@MainActor
final class SumiPaperColourFidelityTests: XCTestCase {
    func testFlatMetalPrintMatchesNativeColourInBothDirections() async throws {
        var measurements: [[String: Any]] = []
        for (name, colourSpaceName) in [("sRGB", CGColorSpace.sRGB), ("DisplayP3", CGColorSpace.displayP3)] {
            let colourSpace = try XCTUnwrap(CGColorSpace(name: colourSpaceName))
            for rightToLeft in [true, false] {
                try await check(name: name, colourSpace: colourSpace, rightToLeft: rightToLeft,
                    measurements: &measurements)
            }
        }
        let data = try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "native-metal-colour-differences"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMovingPaperKeepsTheNativePrintBrightness() async throws {
        guard SumiPageCurlMetalRenderer.isAvailable else { throw XCTSkip("A real GPU pipeline is required for colour fidelity") }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 480, height: 640,
            bitsPerComponent: 8, bytesPerRow: 480 * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(try XCTUnwrap(CGColor(colorSpace: space, components: [0.55, 0.55, 0.55, 1])))
        bitmap.fill(CGRect(x: 0, y: 0, width: 480, height: 640))
        let printImage = UIImage(cgImage: try XCTUnwrap(bitmap.makeImage()))
        let artwork = try XCTUnwrap(SumiPageCurlMetalRenderer.prepareArtwork(front: printImage, back: printImage))
        let bounds = CGRect(x: 0, y: 0, width: 960, height: 640)
        let hardware = try XCTUnwrap(SumiPageCurlMetalRenderer(frame: bounds, artwork: artwork, sign: 1))
        let grip = CGPoint(x: 432, y: 320)
        let deformation = SumiPageCurlDeformation(size: CGSize(width: 480, height: 640), grip: grip)
        for progress: CGFloat in [0.1, 0.25, 0.5, 0.75, 0.9] {
            hardware.update(progress: progress, deformation: deformation)
            let snapshot = try XCTUnwrap(hardware.renderSnapshot(), "Read back the actual current GPU frame")
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1; format.opaque = true; format.preferredRange = .standard
            let capture = UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
                UIColor.systemRed.setFill()
                context.fill(bounds)
                snapshot.draw(in: bounds)
                // These native CG/UI swatches share the exact final capture's
                // output profile with the current GPU frame.
                for y in [CGFloat(0), 580] {
                    printImage.draw(in: CGRect(x: 0, y: y, width: 60, height: 60))
                }
            }
            let paper = deformation.vertex(x: grip.x, y: grip.y, progress: progress)
            let point = CGPoint(x: bounds.midX + paper.paper.x, y: paper.y)
            XCTAssertTrue(bounds.insetBy(dx: 3, dy: 3).contains(point), "The held print must remain visible")
            guard bounds.insetBy(dx: 3, dy: 3).contains(point) else { continue }
            let pixels = try rgbaPixels(capture)
            let reference = pixel(pixels, width: 960, x: 24, y: 24)
            let moving = pixel(pixels, width: 960, x: Int(point.x.rounded()), y: Int(point.y.rounded()))
            let difference = zip(reference, moving).map { abs($0 - $1) }.max() ?? 0
            XCTAssertLessThanOrEqual(difference, 4,
                "The moving print must keep its native brightness at progress \(progress): native \(reference), moving \(moving)")
            let attachment = XCTAttachment(image: capture)
            attachment.name = "constant-print-\(Int(progress * 100))"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func check(name: String, colourSpace: CGColorSpace, rightToLeft: Bool,
                       measurements: inout [[String: Any]]) async throws {
        let bounds = CGRect(x: 0, y: 0, width: 960, height: 640)
        let first = try chart(colourSpace: colourSpace, offset: 0)
        let next = try chart(colourSpace: colourSpace, offset: 3)
        let turn = SumiPageCurlView(frame: bounds, oldImages: [first, first],
            newImages: [next, next], rightToLeft: rightToLeft)
        guard SumiPageCurlMetalRenderer.isAvailable else { throw XCTSkip("A real GPU pipeline is required for colour fidelity") }
        let hardware = try XCTUnwrap(turn.subviews.compactMap { $0 as? SumiPageCurlMetalRenderer }.first,
            "Colour fidelity must exercise Metal, not its native fallback")
        let host = UIViewController()
        host.view.backgroundColor = .black
        host.view.addSubview(turn)
        let window = UIWindow(frame: bounds)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        for progress: CGFloat in [0, 1] {
            turn.update(progress: progress)
            // Component-test windows do not reliably receive normal display
            // invalidation. Explicitly submit the same production draw path.
            hardware.draw()
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while ContinuousClock.now < deadline,
                  hardware.lastRenderedProgress.map({ abs($0 - Float(progress)) > 0.0001 }) ?? true {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertEqual(hardware.lastRenderedProgress ?? -1, Float(progress), accuracy: 0.0001)
            CATransaction.flush()
            try await Task.sleep(for: .milliseconds(60))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            format.preferredRange = .standard
            let capture = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
                XCTAssertTrue(host.view.drawHierarchy(in: bounds, afterScreenUpdates: true))
            }
            let pixels = try rgbaPixels(capture)
            let directSnapshot = try XCTUnwrap(hardware.renderSnapshot(), "Verify actual GPU endpoint pixels")
            let directPixels = try rgbaPixels(directSnapshot)
            let movingIsLeft = rightToLeft ? (progress == 1) : (progress == 0)
            var maximumDifference = 0
            var maximumDirectDifference = 0
            for row in 0..<2 {
                for column in 0..<4 {
                    let x = 60 + column * 120
                    let y = 160 + row * 320
                    let left = pixel(pixels, width: 960, x: x, y: y)
                    let right = pixel(pixels, width: 960, x: x + 480, y: y)
                    let difference = zip(left, right).map { abs($0 - $1) }.max() ?? 0
                    maximumDifference = max(maximumDifference, difference)
                    let direct = pixel(directPixels, width: 960, x: x + (movingIsLeft ? 0 : 480), y: y)
                    let native = movingIsLeft ? right : left
                    let directDifference = zip(native, direct).map { abs($0 - $1) }.max() ?? 0
                    maximumDirectDifference = max(maximumDirectDifference, directDifference)
                    measurements.append(["space": name, "rightToLeft": rightToLeft,
                        "progress": Double(progress), "row": row, "column": column,
                        "leftRGB": left, "rightRGB": right, "maximumChannelDifference": difference,
                        "offscreenRGB": direct, "offscreenMaximumChannelDifference": directDifference])
                }
            }
            let attachment = XCTAttachment(image: capture)
            attachment.name = "flat-colour-\(name)-\(rightToLeft ? "forward" : "reverse")-\(Int(progress))"
            attachment.lifetime = .keepAlways
            add(attachment)
            let directAttachment = XCTAttachment(image: directSnapshot)
            directAttachment.name = "flat-gpu-readback-\(name)-\(rightToLeft ? "forward" : "reverse")-\(Int(progress))"
            directAttachment.lifetime = .keepAlways
            add(directAttachment)
            XCTAssertLessThanOrEqual(maximumDirectDifference, 4,
                "Actual GPU readback must match the native print, including channel order and orientation (\(name), RTL \(rightToLeft), progress \(progress))")
            XCTAssertLessThanOrEqual(maximumDifference, 4,
                "The flat GPU print must match its native neighbour without a brightness or hue jump (\(name), RTL \(rightToLeft), progress \(progress))")
        }
    }

    private func chart(colourSpace: CGColorSpace, offset: Int) throws -> UIImage {
        let colours: [[CGFloat]] = [
            [0.96, 0.94, 0.85], [0.24, 0.35, 0.46], [0.70, 0.40, 0.20], [0.20, 0.60, 0.30],
            [0.95, 0.15, 0.20], [0.15, 0.25, 0.85], [0.65, 0.25, 0.70], [0.50, 0.50, 0.50]
        ]
        let context = try XCTUnwrap(CGContext(data: nil, width: 480, height: 640,
            bitsPerComponent: 8, bytesPerRow: 480 * 4, space: colourSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for index in 0..<8 {
            let colour = try XCTUnwrap(CGColor(colorSpace: colourSpace, components: colours[(index + offset) % 8] + [1]))
            context.setFillColor(colour)
            context.fill(CGRect(x: (index % 4) * 120, y: (index / 4) * 320, width: 120, height: 320))
        }
        return UIImage(cgImage: try XCTUnwrap(context.makeImage()))
    }

    private func rgbaPixels(_ image: UIImage) throws -> [UInt8] {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: 960 * 640 * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 960, height: 640,
                bitsPerComponent: 8, bytesPerRow: 960 * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 960, height: 640))
        }
        return bytes
    }

    private func pixel(_ bytes: [UInt8], width: Int, x: Int, y: Int) -> [Int] {
        let start = (y * width + x) * 4
        return bytes[start..<(start + 3)].map(Int.init)
    }
}
