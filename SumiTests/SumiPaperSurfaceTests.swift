@testable import Sumi
import Testing
import UIKit

@MainActor
struct SumiPaperSurfaceTests {
    @Test("The shared paper stays white, has restrained grain, and preserves solid black ink")
    func printedPaper() throws {
        let tile = SumiPaperSurface.inkTile
        let format = UIGraphicsImageRendererFormat()
        format.scale = tile.scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: tile.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: tile.size))
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: tile.size.width / 2, height: tile.size.height))
            tile.draw(at: .zero)
        }
        let cg = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        var white: [Int] = []
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let offset = (y * cg.width + x) * 4
                #expect(bytes[offset] == bytes[offset + 1] && bytes[offset + 1] == bytes[offset + 2])
                if x < cg.width / 2 { #expect(bytes[offset] == 0) }
                else { white.append(Int(bytes[offset])) }
            }
        }
        #expect(Double(white.reduce(0, +)) / Double(white.count) > 251)
        #expect((white.max() ?? 0) - (white.min() ?? 0) >= 10)
        #expect((white.max() ?? 0) - (white.min() ?? 0) <= 20)
        #expect(SumiPaperSurface.backgroundTile.size == tile.size)
    }
}
