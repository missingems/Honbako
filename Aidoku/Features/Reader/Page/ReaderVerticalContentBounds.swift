import CoreGraphics
import Foundation

/// Presentation-only bounds for verified white vertical margins. The original
/// bitmap and recognition coordinate system always remain unchanged.
struct ReaderVerticalContentBounds: Equatable, Sendable {
    let minY: CGFloat
    let maxY: CGFloat

    static let fullImage = ReaderVerticalContentBounds(minY: 0, maxY: 1)

    func frame(in originalFrame: CGRect) -> CGRect {
        CGRect(x: originalFrame.minX, y: originalFrame.minY + originalFrame.height * minY,
               width: originalFrame.width, height: originalFrame.height * (maxY - minY))
    }

    static func detect(in image: CGImage) -> ReaderVerticalContentBounds {
        let width = image.width
        let height = image.height
        guard width >= 32, height >= 64, width <= 20_000, height <= 50_000,
              width * height <= 100_000_000, image.bitsPerComponent <= 8 else { return .fullImage }
        let minimumMargin = max(6, Int(ceil(Double(height) * 0.008)))
        let gutter = max(3, Int(ceil(Double(height) * 0.004)))
        // A large blank region could be deliberate page composition. Require
        // an actual content boundary within this conservative edge window.
        let limit = Int(Double(height) * 0.2)
        let top = whiteMargin(in: image, fromTop: true, limit: limit) ?? 0
        let bottom = whiteMargin(in: image, fromTop: false, limit: limit) ?? 0
        guard !Task.isCancelled else { return .fullImage }
        let topTrim = top >= minimumMargin ? max(0, top - gutter) : 0
        let bottomTrim = bottom >= minimumMargin ? max(0, bottom - gutter) : 0
        return ReaderVerticalContentBounds(minY: CGFloat(topTrim) / CGFloat(height),
                                           maxY: 1 - CGFloat(bottomTrim) / CGFloat(height))
    }

    private static func whiteMargin(in image: CGImage, fromTop: Bool, limit: Int) -> Int? {
        let width = image.width
        let height = image.height
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var scanned = 0
        while scanned < limit {
            guard !Task.isCancelled else { return nil }
            let rows = min(64, limit - scanned)
            let start = fromTop ? scanned : height - scanned - rows
            guard let strip = image.cropping(to: CGRect(x: 0, y: start, width: width, height: rows)),
                  let context = CGContext(data: nil, width: width, height: rows, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                  let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
            // Transparent pixels are compared against white, never treated as
            // black. Scan at source resolution so small text is not averaged away.
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: rows))
            context.interpolationQuality = .none
            context.draw(strip, in: CGRect(x: 0, y: 0, width: width, height: rows))
            for index in 0..<rows {
                let row = fromTop ? index : rows - 1 - index
                let offset = row * context.bytesPerRow
                for x in 0..<width {
                    let pixel = offset + x * 4
                    // Preserve even faint marks, colored paper and dark borders.
                    if bytes[pixel] < 250 || bytes[pixel + 1] < 250 || bytes[pixel + 2] < 250 {
                        return scanned + index
                    }
                }
            }
            scanned += rows
        }
        return nil
    }
}
