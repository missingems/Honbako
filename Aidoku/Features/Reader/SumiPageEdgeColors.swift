#if SUMI
import Foundation
import UIKit

/// Colors come from four independently sampled bitmap edges. A dominant real
/// sample keeps a little edge text from turning white paper or black ink gray.
struct SumiPageEdgeColors: Equatable, Sendable {
    struct Color: Equatable, Sendable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8

        var uiColor: UIColor {
            UIColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
        }
    }

    let top: Color
    let leading: Color
    let trailing: Color
    let bottom: Color

    static func identity(image: CGImage, orientation: UIImage.Orientation, crop: CGRect) -> String {
        "\(ObjectIdentifier(image))-\(cropIdentity(image: image, orientation: orientation, crop: crop))"
    }

    static func cropIdentity(image: CGImage, orientation: UIImage.Orientation, crop: CGRect) -> String {
        let size = displaySize(image: image, orientation: orientation)
        return "\(orientation.rawValue)-\(Int((crop.minX * size.width).rounded()))-\(Int((crop.minY * size.height).rounded()))-\(Int((crop.maxX * size.width).rounded()))-\(Int((crop.maxY * size.height).rounded()))"
    }

    static func sample(image: CGImage, orientation: UIImage.Orientation = .up,
                       crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> Self? {
        guard image.width > 0, image.height > 0,
              [crop.minX, crop.minY, crop.width, crop.height].allSatisfy(\.isFinite) else { return nil }
        let crop = crop.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !crop.isEmpty, !crop.isNull else { return nil }
        let size = displaySize(image: image, orientation: orientation)
        // Use pixel centers inside the visible crop, including an internal
        // split edge. This does not accidentally sample the neighboring leaf.
        let left = min(crop.midX, crop.minX + 0.5 / size.width)
        let right = max(crop.midX, crop.maxX - 0.5 / size.width)
        let top = min(crop.midY, crop.minY + 0.5 / size.height)
        let bottom = max(crop.midY, crop.maxY - 0.5 / size.height)
        func edge(_ start: CGPoint, _ end: CGPoint) -> Color? {
            guard !Task.isCancelled else { return nil }
            let first = sourcePoint(start, image: image, orientation: orientation)
            let last = sourcePoint(end, image: image, orientation: orientation)
            let rect = CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                              width: abs(last.x - first.x) + 1, height: abs(last.y - first.y) + 1)
            guard let strip = image.cropping(to: rect) else { return nil }
            return dominantColor(in: strip)
        }
        guard let topColor = edge(CGPoint(x: left, y: top), CGPoint(x: right, y: top)),
              let leading = edge(CGPoint(x: left, y: top), CGPoint(x: left, y: bottom)),
              let trailing = edge(CGPoint(x: right, y: top), CGPoint(x: right, y: bottom)),
              let bottomColor = edge(CGPoint(x: left, y: bottom), CGPoint(x: right, y: bottom)) else { return nil }
        let result = Self(top: topColor, leading: leading, trailing: trailing, bottom: bottomColor)
        return result
    }

    private static func displaySize(image: CGImage, orientation: UIImage.Orientation) -> CGSize {
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            return CGSize(width: image.height, height: image.width)
        default:
            return CGSize(width: image.width, height: image.height)
        }
    }

    private static func sourcePoint(_ point: CGPoint, image: CGImage, orientation: UIImage.Orientation) -> CGPoint {
        let raw: CGPoint
        switch orientation {
        case .up: raw = point
        case .down: raw = CGPoint(x: 1 - point.x, y: 1 - point.y)
        case .left: raw = CGPoint(x: 1 - point.y, y: point.x)
        case .right: raw = CGPoint(x: point.y, y: 1 - point.x)
        case .upMirrored: raw = CGPoint(x: 1 - point.x, y: point.y)
        case .downMirrored: raw = CGPoint(x: point.x, y: 1 - point.y)
        case .leftMirrored: raw = CGPoint(x: point.y, y: point.x)
        case .rightMirrored: raw = CGPoint(x: 1 - point.y, y: 1 - point.x)
        @unknown default: raw = point
        }
        return CGPoint(x: min(image.width - 1, max(0, Int(floor(raw.x * CGFloat(image.width))))),
                       y: min(image.height - 1, max(0, Int(floor(raw.y * CGFloat(image.height))))))
    }

    private static func dominantColor(in strip: CGImage) -> Color? {
        let vertical = strip.height > strip.width
        let count = min(256, vertical ? strip.height : strip.width)
        let width = vertical ? 1 : count
        let height = vertical ? count : 1
        var pixels = [UInt8](repeating: 255, count: count * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .none
            context.draw(strip, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }
        var bins: [Int: [Color]] = [:]
        for index in 0..<count {
            let offset = index * 4
            let color = Color(red: pixels[offset], green: pixels[offset + 1], blue: pixels[offset + 2])
            let bin = Int(color.red >> 4) << 8 | Int(color.green >> 4) << 4 | Int(color.blue >> 4)
            bins[bin, default: []].append(color)
        }
        guard let dominant = bins.max(by: { lhs, rhs in
            lhs.value.count == rhs.value.count ? lhs.key < rhs.key : lhs.value.count < rhs.value.count
        })?.value else { return nil }
        let median = Color(red: dominant.map(\.red).sorted()[dominant.count / 2],
                           green: dominant.map(\.green).sorted()[dominant.count / 2],
                           blue: dominant.map(\.blue).sorted()[dominant.count / 2])
        func distance(_ color: Color) -> Int {
            abs(Int(color.red) - Int(median.red)) + abs(Int(color.green) - Int(median.green)) + abs(Int(color.blue) - Int(median.blue))
        }
        // Select an actual sampled pixel instead of synthesizing a mixed RGB.
        return dominant.min { distance($0) < distance($1) }
    }
}
#endif
