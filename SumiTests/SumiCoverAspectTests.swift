@testable import Sumi
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiCoverAspectTests {
    @Test("Wide and tall cover prints keep circular artwork round in the grid and lifted source")
    func proportionalGridAndPickup() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .alert + 1
        let host = UIViewController()
        host.view.backgroundColor = .white
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            let wasKey = window.isKeyWindow
            window.isHidden = true
            window.rootViewController = nil
            if wasKey { previousKeyWindow?.makeKey() }
        }
        for size in [CGSize(width: 400, height: 200), CGSize(width: 100, height: 400)] {
            let view = SumiGridBookView(frame: CGRect(x: 20, y: 40, width: 136, height: 200))
            let print = artwork(size: size)
            view.applyFlatEdition(cover: print)
            host.view.addSubview(view)
            window.layoutIfNeeded()
            let expected = min(size.width, size.height) * 0.5
                * max(view.bounds.width / size.width, view.bounds.height / size.height)
            try assertRoundPrint(view, expectedDiameter: expected)
            let source = try #require(SumiBookTransitionSource.capture(view))
            defer { source.finish(); view.removeFromSuperview() }
            #expect(source.coverArtwork === print, "Framing must not destructively replace the original provider artwork")
            try assertRoundPrint(source.view, expectedDiameter: expected)
        }
    }

    private func artwork(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let diameter = min(size.width, size.height) * 0.5
            UIColor.black.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: (size.width - diameter) / 2,
                y: (size.height - diameter) / 2, width: diameter, height: diameter))
        }
    }

    private func assertRoundPrint(_ view: UIView, expectedDiameter: CGFloat) throws {
        view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let raster = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }
        let image = try #require(raster.cgImage)
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        func isInk(x: Int, y: Int) -> Bool {
            let offset = (y * width + x) * 4
            return pixels[offset] < 64 && pixels[offset + 1] < 64 && pixels[offset + 2] < 64
                && pixels[offset + 3] > 200
        }
        let horizontal = (0..<width).filter { isInk(x: $0, y: height / 2) }.count
        let vertical = (0..<height).filter { isInk(x: width / 2, y: $0) }.count
        #expect(abs(horizontal - vertical) <= 2, "The cover's circle was squeezed: \(horizontal) × \(vertical)")
        #expect(abs(CGFloat(horizontal) - expectedDiameter) <= 2,
                "The cover should fill its slot with proportional cropping, not shrink inside it")
    }
}
