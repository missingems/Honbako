@testable import Sumi
import Testing
import UIKit

@MainActor
@Suite struct HonbakoJapaneseSnapshotTests {
    @Test("Paper snapshots contain manga artwork without live Japanese labels")
    func excludesLiveLabelsFromPaper() throws {
        let bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
        let paper = UIView(frame: bounds)
        paper.backgroundColor = UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1)
        let artwork = try centerPixel(in: capture(paper))
        let labels = HonbakoInlineJapaneseOverlayView()
        labels.frame = bounds
        labels.backgroundColor = UIColor(red: 0.8, green: 0.1, blue: 0.2, alpha: 1)
        paper.addSubview(labels)
        // Settle the detached fixture's eligibility layout before making the
        // colored annotation visible for this synchronous raster comparison.
        paper.layoutIfNeeded()
        labels.layoutIfNeeded()
        labels.isHidden = false
        #expect(try centerPixel(in: capture(paper)) != artwork)

        let texture = HonbakoInlineJapaneseOverlayView.withSnapshotsSuppressed(in: paper) {
            capture(paper)
        }
        #expect(try centerPixel(in: texture) == artwork)
        #expect(!labels.isHidden)
        #expect(try centerPixel(in: capture(paper)) != artwork)
    }

    @Test("Nested capture restores host state and leaves another reader alone")
    func captureIsScopedAndRestoresState() {
        let page = UIView()
        let visible = HonbakoInlineJapaneseOverlayView()
        let alreadyHidden = HonbakoInlineJapaneseOverlayView()
        let anotherReader = HonbakoInlineJapaneseOverlayView()
        page.addSubview(visible)
        page.addSubview(alreadyHidden)
        visible.isHidden = false
        visible.alpha = 0.6
        alreadyHidden.isHidden = true
        anotherReader.isHidden = false

        let value = HonbakoInlineJapaneseOverlayView.withSnapshotsSuppressed(in: page) {
            #expect(visible.isHidden)
            #expect(alreadyHidden.isHidden)
            #expect(!anotherReader.isHidden)
            HonbakoInlineJapaneseOverlayView.withSnapshotsSuppressed(in: visible) {
                #expect(visible.isHidden)
            }
            #expect(visible.isHidden)
            return 7
        }
        #expect(value == 7)
        #expect(!visible.isHidden)
        #expect(abs(visible.alpha - 0.6) < 0.000001)
        #expect(alreadyHidden.isHidden)
        #expect(!anotherReader.isHidden)

        HonbakoInlineJapaneseOverlayView.withSnapshotsSuppressed(in: visible) {
            #expect(visible.isHidden)
        }
        #expect(!visible.isHidden)
    }

    private func capture(_ view: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }
    }

    private func centerPixel(in image: UIImage) throws -> [UInt8] {
        let image = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let offset = ((image.height / 2) * image.width + image.width / 2) * 4
        return Array(bytes[offset..<(offset + 4)])
    }
}
