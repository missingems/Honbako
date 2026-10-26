#if SUMI
import UIKit

/// One cached paper stock for manga page margins and printed artwork.
/// The transparent black grain leaves solid manga ink intact.
enum SumiPaperSurface {
    static let inkTile: UIImage = {
        var bytes = [UInt8](ReaderPaperTexture.tileData(strength: .light))
        for index in stride(from: 3, to: bytes.count, by: 4) {
            // Remove the uniform gray wash; retain the grain and raised fibers.
            bytes[index] = UInt8(min(20, max(0, Int(bytes[index]) - 13) * 2 / 3))
        }
        let side = ReaderPaperTexture.tileSize
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return UIImage(cgImage: image, scale: CGFloat(side) / ReaderPaperTexture.tilePointSize, orientation: .up)
    }()

    static let backgroundTile: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = inkTile.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: inkTile.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: inkTile.size))
            inkTile.draw(at: .zero)
        }
    }()

    static let backgroundColor = UIColor(patternImage: backgroundTile)
    static let inkColor = UIColor(patternImage: inkTile)
}
#endif
