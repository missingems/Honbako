import CoreGraphics

/// Decode once per recognized page, off the main thread. Ink follows the page,
/// never the interface's light/dark appearance. Input is orientation-normalized.
struct HonbakoJapaneseInkSampler {
    private let pixels: [UInt8]
    private let width: Int
    private let height: Int

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        self.width = width
        self.height = height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        pixels = bytes
    }

    func ink(in normalizedBox: CGRect) -> HonbakoJapaneseInk {
        let box = CGRect(x: normalizedBox.minX * CGFloat(width), y: normalizedBox.minY * CGFloat(height),
            width: normalizedBox.width * CGFloat(width), height: normalizedBox.height * CGFloat(height))
        guard box.width >= 1, box.height >= 1 else { return .black }
        let expanded = box.insetBy(dx: -max(2, box.width * 0.15), dy: -max(2, box.height * 0.15))
        let background = samples(in: expanded).filter { !box.contains($0.point) }.map(\.color)
        let interior = samples(in: box).map(\.color)
        guard !interior.isEmpty else { return .black }
        let backgroundLuma = median(background.map(luminance)) ?? median(interior.map(luminance)) ?? 255
        // OCR rectangles contain antialiasing and paper too. Use the opposite
        // luminance tail from the surrounding paper, then its median ink pixel.
        let sorted = interior.sorted { luminance($0) < luminance($1) }
        let count = max(1, sorted.count / 5)
        let ink = backgroundLuma >= 128 ? Array(sorted.prefix(count)) : Array(sorted.suffix(count))
        return ink[ink.count / 2]
    }

    private func samples(in box: CGRect) -> [(point: CGPoint, color: HonbakoJapaneseInk)] {
        let minX = max(0, Int(floor(box.minX))), maxX = min(width, Int(ceil(box.maxX)))
        let minY = max(0, Int(floor(box.minY))), maxY = min(height, Int(ceil(box.maxY)))
        guard minX < maxX, minY < maxY else { return [] }
        let stride = max(1, Int(sqrt(Double((maxX - minX) * (maxY - minY)) / 4096)))
        var result: [(CGPoint, HonbakoJapaneseInk)] = []
        for y in Swift.stride(from: minY, to: maxY, by: stride) {
            for x in Swift.stride(from: minX, to: maxX, by: stride) {
                let offset = (y * width + x) * 4
                result.append((CGPoint(x: x, y: y), .init(red: pixels[offset], green: pixels[offset + 1], blue: pixels[offset + 2])))
            }
        }
        return result
    }

    private func luminance(_ ink: HonbakoJapaneseInk) -> Double {
        0.2126 * Double(ink.red) + 0.7152 * Double(ink.green) + 0.0722 * Double(ink.blue)
    }

    private func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        return sorted.isEmpty ? nil : sorted[sorted.count / 2]
    }
}
