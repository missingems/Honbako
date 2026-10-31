@testable import Sumi
import CoreGraphics
import Foundation
import Testing

@Suite struct HonbakoJapaneseInkTests {
    @Test("Plain annotations follow black or white page ink, independently of interface appearance")
    func pageInk() throws {
        for whiteInk in [false, true] {
            let background: UInt8 = whiteInk ? 0 : 255
            let foreground: UInt8 = whiteInk ? 255 : 0
            var bytes = [UInt8](repeating: background, count: 100 * 100 * 4)
            for y in 0..<100 {
                for x in 0..<100 {
                    let offset = (y * 100 + x) * 4
                    if (42..<49).contains(x), (15..<30).contains(y) {
                        bytes[offset] = foreground; bytes[offset + 1] = foreground; bytes[offset + 2] = foreground
                    }
                    bytes[offset + 3] = 255
                }
            }
            let data = try #require(CGDataProvider(data: Data(bytes) as CFData))
            let image = try #require(CGImage(width: 100, height: 100, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: data, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            let sampler = try #require(HonbakoJapaneseInkSampler(image: image))
            #expect(sampler.ink(in: CGRect(x: 0.4, y: 0.15, width: 0.12, height: 0.15)) == (whiteInk ? .white : .black))
        }
    }
}
