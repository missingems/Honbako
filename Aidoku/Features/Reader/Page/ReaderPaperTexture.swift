//
//  ReaderPaperTexture.swift
//  Aidoku
//

import UIKit

enum ReaderPaperTexture {
    static let tileSize = 256
    static let tilePointSize: CGFloat = 128

    /// Neutral paper at several scales: broad surface variation, visible grain,
    /// and sparse light/dark fibers. Black-only alpha preserves solid ink.
    static func tileData(strength: ReaderPaperTextureStrength = .strong, seed: UInt32 = 0xA1D0_2026) -> Data {
        var state = seed == 0 ? 1 : seed
        func random() -> UInt32 {
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            return state
        }
        let broad = (0..<256).map { _ in UInt8(random() & 255) }
        let grain = (0..<4096).map { _ in UInt8(random() & 255) }

        // Wrap grid coordinates so the cached tile has no visible seams.
        func noise(_ grid: [UInt8], cell: Int, x: Int, y: Int) -> Int {
            let width = tileSize / cell
            let column = x / cell
            let row = y / cell
            let u = Double(x % cell) / Double(cell)
            let v = Double(y % cell) / Double(cell)
            let sx = u * u * (3 - 2 * u)
            let sy = v * v * (3 - 2 * v)
            func sample(_ dx: Int, _ dy: Int) -> Double {
                Double(grid[((row + dy) % width) * width + (column + dx) % width])
            }
            let top = sample(0, 0) * (1 - sx) + sample(1, 0) * sx
            let bottom = sample(0, 1) * (1 - sx) + sample(1, 1) * sx
            return Int(top * (1 - sy) + bottom * sy)
        }

        var bytes = [UInt8](repeating: 0, count: tileSize * tileSize * 4)
        for y in 0..<tileSize {
            for x in 0..<tileSize {
                let alpha = 2 + noise(broad, cell: 16, x: x, y: y) * 10 / 255
                    + noise(grain, cell: 4, x: x, y: y) * 8 / 255 + Int(random() & 7)
                bytes[(y * tileSize + x) * 4 + 3] = UInt8(alpha)
            }
        }
        for index in 0..<64 {
            let startX = Double(random() % UInt32(tileSize))
            let startY = Double(random() % UInt32(tileSize))
            let angle = Double(random() % 6283) / 1000
            let length = Int(random() % 19) + 8
            let strength = index.isMultiple(of: 3) ? -8 : 16
            for step in 0..<length {
                let x = Int((startX + cos(angle) * Double(step)).rounded())
                let y = Int((startY + sin(angle) * Double(step)).rounded())
                let pixel = ((y + tileSize) % tileSize * tileSize + (x + tileSize) % tileSize) * 4 + 3
                // Repeated raster steps must not turn a fiber into a dark scratch.
                let value = Int(bytes[pixel]) + strength
                bytes[pixel] = UInt8(max(1, min(44, value)))
            }
        }
        // Preserve clean white highlights while increasing the contrast of
        // the surface. Scaling the entire old wash would only make paper gray.
        if strength != .light {
            let floor = strength == .strong ? 5 : 4
            let contrast = strength == .strong ? 2.8 : 1.8
            let limit = strength == .strong ? 80 : 64
            for pixel in 0..<(tileSize * tileSize) {
                let index = pixel * 4 + 3
                bytes[index] = UInt8(min(limit, Int((Double(max(0, Int(bytes[index]) - floor)) * contrast).rounded())))
            }
        }
        return Data(bytes)
    }

    // Three small shared tiles, never a processed copy of a full manga page.
    private static let tiles: [ReaderPaperTextureStrength: CGImage] = {
        var result: [ReaderPaperTextureStrength: CGImage] = [:]
        for strength in ReaderPaperTextureStrength.allCases {
            guard let provider = CGDataProvider(data: tileData(strength: strength) as CFData),
                  let image = CGImage(
                    width: tileSize, height: tileSize,
                    bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: tileSize * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
                  ) else { continue }
            result[strength] = image
        }
        return result
    }()

    static func image(displayScale _: CGFloat, strength: ReaderPaperTextureStrength = .strong) -> UIImage? {
        // Keep fibers at the same readable point size on 2x/3x displays rather
        // than shrinking the entire effect as display density increases.
        tiles[strength].map { UIImage(cgImage: $0, scale: CGFloat(tileSize) / tilePointSize, orientation: .up) }
    }
}
