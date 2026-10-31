#if SUMI
import CoreGraphics
import Foundation
import Metal

/// Native image layers colour-match their CGImage profiles. The moving paper
/// uses one explicit Display P3 colour space, including its sRGB transfer curve.
@MainActor
enum SumiPaperColourSpace {
    static let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)

    /// Core Graphics bitmap RGB is premultiplied in its encoded transfer space.
    /// A GPU sRGB sampler instead needs encoded *linear-premultiplied* RGB, so
    /// interpolation and .one blending remain correct at translucent paper edges.
    private static let linearPremultiplication: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 256 * 256)
        for alpha in 1...255 {
            let opacity = Double(alpha) / 255
            for component in 0...255 {
                let encoded = min(1, Double(component) / Double(alpha))
                let linear = encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
                let premultiplied = linear * opacity
                let result = premultiplied <= 0.0031308 ? premultiplied * 12.92
                    : 1.055 * pow(premultiplied, 1 / 2.4) - 0.055
                table[alpha * 256 + component] = UInt8(clamping: Int((result * 255).rounded()))
            }
        }
        return table
    }()

    #if DEBUG
    /// Convert a GPU render target back into a CGImage's encoded-premultiplied
    /// convention. This is verification-only; production frames never read back.
    static func image(fromEncodedLinearPremultipliedBGRA pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let displayP3, width > 0, height > 0, pixels.count == width * height * 4 else { return nil }
        var converted = pixels
        for index in stride(from: 0, to: converted.count, by: 4) {
            let alpha = Int(converted[index + 3])
            if alpha == 255 { continue }
            if alpha == 0 {
                converted[index] = 0; converted[index + 1] = 0; converted[index + 2] = 0
            } else {
                let start = alpha * 256
                converted[index] = encodedPremultiplication[start + Int(converted[index])]
                converted[index + 1] = encodedPremultiplication[start + Int(converted[index + 1])]
                converted[index + 2] = encodedPremultiplication[start + Int(converted[index + 2])]
            }
        }
        guard let provider = CGDataProvider(data: Data(converted) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: displayP3,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static let encodedPremultiplication: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 256 * 256)
        for alpha in 1...255 {
            let opacity = Double(alpha) / 255
            for component in 0...255 {
                let encoded = Double(component) / 255
                let premultiplied = encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
                let linear = min(1, premultiplied / opacity)
                let straight = linear <= 0.0031308 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055
                table[alpha * 256 + component] = UInt8(clamping: Int((straight * opacity * 255).rounded()))
            }
        }
        return table
    }()
    #endif

    static func makeTexture(from image: CGImage, device: MTLDevice) -> MTLTexture? {
        guard let displayP3 else { return nil }
        let width = image.width, height = image.height
        // Bound transient conversion memory before asking the device to allocate.
        guard width > 0, height > 0, width <= 16_384, height <= 16_384,
              width <= 32_000_000 / height else { return nil }
        let rowBytes = width * 4
        guard let bitmap = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: rowBytes, space: displayP3,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let storage = bitmap.data else { return nil }
        bitmap.setBlendMode(.copy)
        bitmap.interpolationQuality = .none
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = storage.assumingMemoryBound(to: UInt8.self)
        for index in stride(from: 0, to: rowBytes * height, by: 4) {
            let alpha = Int(pixels[index + 3])
            if alpha == 255 { continue }
            if alpha == 0 {
                pixels[index] = 0; pixels[index + 1] = 0; pixels[index + 2] = 0
            } else {
                let start = alpha * 256
                pixels[index] = linearPremultiplication[start + Int(pixels[index])]
                pixels[index + 1] = linearPremultiplication[start + Int(pixels[index + 1])]
                pixels[index + 2] = linearPremultiplication[start + Int(pixels[index + 2])]
            }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb,
            width: width, height: height, mipmapped: true)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
            withBytes: storage, bytesPerRow: rowBytes)
        return texture
    }
}
#endif
