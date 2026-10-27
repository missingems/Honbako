#if SUMI
import Foundation
@preconcurrency import MetalKit
import UIKit

/// Runs once on Nuke's processing queue. Tiles and book transitions display the
/// cached bitmap, without a render loop, moving shadows, or a second material.
final class HonbakoCoverMetalRenderer: @unchecked Sendable {
    static let shared = HonbakoCoverMetalRenderer()

    private let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLComputePipelineState
    private let reportLock = NSLock()
    private var reported = false

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let function = device.makeDefaultLibrary()?.makeFunction(name: "honbako_cover_material"),
              let pipeline = try? device.makeComputePipelineState(function: function) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }

    func render(_ image: UIImage) -> UIImage? {
        guard let original = image.cgImage, image.imageOrientation == .up else { return nil }
        let loader = MTKTextureLoader(device: device)
        guard let input = try? loader.newTexture(cgImage: original, options: [
            .SRGB: false, .origin: MTKTextureLoader.Origin.topLeft.rawValue,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
        ]) else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: input.width, height: input.height, mipmapped: false)
        descriptor.usage = [.shaderWrite, .shaderRead]
        descriptor.storageMode = .shared
        guard let output = device.makeTexture(descriptor: descriptor),
              let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { return nil }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        let width = pipeline.threadExecutionWidth
        let group = MTLSize(width: width, height: max(1, min(8, pipeline.maxTotalThreadsPerThreadgroup / width)), depth: 1)
        encoder.dispatchThreads(MTLSize(width: input.width, height: input.height, depth: 1), threadsPerThreadgroup: group)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return nil }

        let rowBytes = output.width * 4
        var pixels = Data(count: rowBytes * output.height)
        pixels.withUnsafeMutableBytes { bytes in
            guard let address = bytes.baseAddress else { return }
            output.getBytes(address, bytesPerRow: rowBytes,
                from: MTLRegionMake2D(0, 0, output.width, output.height), mipmapLevel: 0)
        }
        guard let colorSpace = original.colorSpace.flatMap({ $0.model == .rgb ? $0 : nil })
            ?? CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let provider = CGDataProvider(data: pixels as CFData),
              let bitmap = CGImage(width: output.width, height: output.height,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes, space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                    .union(.byteOrder32Little), provider: provider, decode: nil,
                shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        reportOnce(width: bitmap.width, height: bitmap.height)
        return UIImage(cgImage: bitmap, scale: image.scale, orientation: .up)
    }

    private func reportOnce(width: Int, height: Int) {
        guard HonbakoProStore.personalFeaturesEnabled else { return }
        reportLock.lock()
        defer { reportLock.unlock() }
        guard !reported else { return }
        let status: [String: Any] = ["renderer": "Metal", "material": "printed-cover-v1",
            "rendered": true, "pixelWidth": width, "pixelHeight": height,
            "updatedAt": Date.now.ISO8601Format()]
        guard let data = try? JSONSerialization.data(withJSONObject: status, options: [.sortedKeys]) else { return }
        do {
            try data.write(to: URL.documentsDirectory.appending(path: "HonbakoCoverMaterialStatus.json"), options: .atomic)
            reported = true
        } catch { }
    }
}
#endif
