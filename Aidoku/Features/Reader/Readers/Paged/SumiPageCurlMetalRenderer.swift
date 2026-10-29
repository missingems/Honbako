#if SUMI
import MetalKit
import UIKit

/// One indexed, double-sided paper mesh. The GPU interpolates real triangles,
/// including edge-on folds where a rectangular homography has a pole.
@MainActor
final class SumiPageCurlMetalRenderer: MTKView, @preconcurrency MTKViewDelegate {
    struct Artwork {
        fileprivate let front: MTLTexture
        fileprivate let back: MTLTexture
    }

    private struct Uniforms {
        var viewport: SIMD2<Float>
        var grip: SIMD2<Float>
        var progress: Float
        var verticalBend: Float
        var sign: Float
        var padding: Float = 0
    }

    private struct Resources {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipeline: MTLRenderPipelineState
        let depth: MTLDepthStencilState
        let sampler: MTLSamplerState
        let sampleCount: Int
        let transientStorageMode: MTLStorageMode
        let vertices: MTLBuffer
        let indices: MTLBuffer
        let indexCount: Int
    }

    private static let resources: Resources? = {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "honbakoPaperVertex"),
              let fragment = library.makeFunction(name: "honbakoPaperFragment") else { return nil }
        let sampleCount = device.supportsTextureSampleCount(4) ? 4 : 1
        let transientStorageMode: MTLStorageMode = device.supportsFamily(.apple1) ? .memoryless : .private
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.maxAnisotropy = 8
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.normalizedCoordinates = true
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.rasterSampleCount = sampleCount
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.depthAttachmentPixelFormat = .depth32Float
        let colour = descriptor.colorAttachments[0]!
        colour.isBlendingEnabled = true
        // Canonical textures decode to linear-premultiplied Display P3 RGB.
        colour.sourceRGBBlendFactor = .one
        colour.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colour.sourceAlphaBlendFactor = .one
        colour.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = true
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let depth = device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }
        let columns = 128, rows = 32
        var vertices: [SIMD2<Float>] = []
        var indices: [UInt16] = []
        for row in 0...rows {
            for column in 0...columns {
                vertices.append(SIMD2(Float(column) / Float(columns), Float(row) / Float(rows)))
            }
        }
        for row in 0..<rows {
            for column in 0..<columns {
                let a = UInt16(row * (columns + 1) + column)
                let b = a + 1
                let d = UInt16((row + 1) * (columns + 1) + column)
                let c = d + 1
                indices.append(contentsOf: [a, b, c, a, c, d])
            }
        }
        guard let vertexBuffer = device.makeBuffer(bytes: vertices,
            length: vertices.count * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared),
              let indexBuffer = device.makeBuffer(bytes: indices,
            length: indices.count * MemoryLayout<UInt16>.stride, options: .storageModeShared) else { return nil }
        return Resources(device: device, queue: queue, pipeline: pipeline, depth: depth,
            sampler: sampler, sampleCount: sampleCount, transientStorageMode: transientStorageMode,
            vertices: vertexBuffer, indices: indexBuffer, indexCount: indices.count)
    }()

    /// Artwork preparation runs before a turn or a complete scrub route starts.
    static func prepareArtwork(front: UIImage, back: UIImage) -> Artwork? {
        guard let resources, let frontImage = front.cgImage, let backImage = back.cgImage else { return nil }
        guard let front = SumiPaperColourSpace.makeTexture(from: frontImage, device: resources.device),
              let back = SumiPaperColourSpace.makeTexture(from: backImage, device: resources.device) else { return nil }
        guard let command = resources.queue.makeCommandBuffer(),
              let blit = command.makeBlitCommandEncoder() else { return nil }
        blit.label = "Honbako prepared paper mipmaps"
        blit.generateMipmaps(for: front)
        blit.generateMipmaps(for: back)
        blit.endEncoding()
        // Every render pass uses this same queue, so the complete mip chain is
        // ready before it samples the print. No finger-frame CPU wait is needed.
        command.commit()
        return Artwork(front: front, back: back)
    }

    static var isAvailable: Bool { resources != nil }
    private(set) var hasRenderedFrame = false
    private(set) var lastRenderedProgress: Float?
    var didRenderFirstFrame: (() -> Void)?
    private var artworkGeneration = UUID()

    private struct Attachments {
        let width: Int
        let height: Int
        let multisampleColour: MTLTexture?
        let depth: MTLTexture
    }

    private var displayAttachments: Attachments?
    private let shared: Resources
    private var artwork: Artwork
    private var uniforms: Uniforms

    init?(frame: CGRect, artwork: Artwork, sign: CGFloat) {
        guard let resources = Self.resources else { return nil }
        self.shared = resources
        self.artwork = artwork
        uniforms = Uniforms(viewport: SIMD2(Float(frame.width), Float(frame.height)),
            grip: SIMD2(Float(frame.width * 0.425), Float(frame.height * 0.75)),
            progress: 0, verticalBend: 0, sign: Float(sign))
        super.init(frame: frame, device: resources.device)
        isOpaque = false
        backgroundColor = .clear
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        colorPixelFormat = .bgra8Unorm_srgb
        (layer as? CAMetalLayer)?.colorspace = SumiPaperColourSpace.displayP3
        depthStencilPixelFormat = .depth32Float
        depthStencilStorageMode = resources.transientStorageMode
        sampleCount = resources.sampleCount
        clearDepth = 1
        framebufferOnly = true
        isPaused = true
        enableSetNeedsDisplay = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        delegate = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func replaceArtwork(_ artwork: Artwork) {
        self.artwork = artwork
        artworkGeneration = UUID()
        hasRenderedFrame = false
        lastRenderedProgress = nil
        setNeedsDisplay()
    }

    func update(progress: CGFloat, deformation: SumiPageCurlDeformation) {
        uniforms.viewport = SIMD2(Float(bounds.width), Float(bounds.height))
        uniforms.grip = SIMD2(Float(deformation.grip.x), Float(deformation.grip.y))
        uniforms.progress = Float(min(1, max(0, progress)))
        uniforms.verticalBend = Float(deformation.verticalBend)
        // Coalesce touch samples and the animation clock at the next display pass.
        setNeedsDisplay()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func encode(descriptor: MTLRenderPassDescriptor, command: MTLCommandBuffer) -> Bool {
        guard let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return false }
        encoder.label = "Honbako physical paper"
        encoder.setRenderPipelineState(shared.pipeline)
        encoder.setDepthStencilState(shared.depth)
        encoder.setFragmentSamplerState(shared.sampler, index: 0)
        encoder.setCullMode(.none)
        encoder.setFrontFacing(uniforms.sign > 0 ? .clockwise : .counterClockwise)
        encoder.setVertexBuffer(shared.vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentTexture(artwork.front, index: 0)
        encoder.setFragmentTexture(artwork.back, index: 1)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: shared.indexCount,
            indexType: .uint16, indexBuffer: shared.indices, indexBufferOffset: 0)
        encoder.endEncoding()
        return true
    }

    private func makeAttachments(width: Int, height: Int) -> Attachments? {
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
            width: width, height: height, mipmapped: false)
        depthDescriptor.usage = .renderTarget
        depthDescriptor.storageMode = shared.transientStorageMode
        depthDescriptor.sampleCount = shared.sampleCount
        depthDescriptor.textureType = shared.sampleCount > 1 ? .type2DMultisample : .type2D
        guard let depth = shared.device.makeTexture(descriptor: depthDescriptor) else { return nil }
        var multisampleColour: MTLTexture?
        if shared.sampleCount > 1 {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
                width: width, height: height, mipmapped: false)
            descriptor.textureType = .type2DMultisample
            descriptor.sampleCount = shared.sampleCount
            descriptor.usage = .renderTarget
            descriptor.storageMode = shared.transientStorageMode
            guard let colour = shared.device.makeTexture(descriptor: descriptor) else { return nil }
            multisampleColour = colour
        }
        return Attachments(width: width, height: height, multisampleColour: multisampleColour, depth: depth)
    }

    private func renderPass(resolvingInto colour: MTLTexture, attachments: Attachments) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = attachments.multisampleColour ?? colour
        pass.colorAttachments[0].resolveTexture = attachments.multisampleColour == nil ? nil : colour
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = attachments.multisampleColour == nil ? .store : .multisampleResolve
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.depthAttachment.texture = attachments.depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1
        return pass
    }

    #if DEBUG
    private var lastSnapshotAttachmentBytes = 0
    var renderingMemoryInfo: [String: Int] {
        ["sampleCount": shared.sampleCount, "frontMipLevels": artwork.front.mipmapLevelCount,
         "backMipLevels": artwork.back.mipmapLevelCount,
         "printTextureBytes": artwork.front.allocatedSize + artwork.back.allocatedSize,
         "transientStorageMode": Int(shared.transientStorageMode.rawValue),
         "displayTransientBytes": (displayAttachments?.multisampleColour?.allocatedSize ?? 0)
            + (displayAttachments?.depth.allocatedSize ?? 0),
         "lastSnapshotTransientBytes": lastSnapshotAttachmentBytes]
    }

    /// Deterministic verification using the exact production pipeline, mesh,
    /// uniforms and textures. No drawable, compositor cache or window is involved.
    /// Blocking/readback is deliberately unavailable in release builds.
    func renderSnapshot() -> UIImage? {
        let width = Int(bounds.width.rounded()), height = Int(bounds.height.rounded())
        guard width > 0, height > 0, width <= 2_048, height <= 2_048 else { return nil }
        let colourDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
            width: width, height: height, mipmapped: false)
        colourDescriptor.usage = .renderTarget
        colourDescriptor.storageMode = .shared
        guard let colour = shared.device.makeTexture(descriptor: colourDescriptor),
              let attachments = makeAttachments(width: width, height: height),
              let command = shared.queue.makeCommandBuffer() else { return nil }
        lastSnapshotAttachmentBytes = (attachments.multisampleColour?.allocatedSize ?? 0) + attachments.depth.allocatedSize
        let pass = renderPass(resolvingInto: colour, attachments: attachments)
        guard encode(descriptor: pass, command: command) else { return nil }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return nil }
        let rowBytes = width * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * height)
        pixels.withUnsafeMutableBytes { buffer in
            colour.getBytes(buffer.baseAddress!, bytesPerRow: rowBytes,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        guard let image = SumiPaperColourSpace.image(fromEncodedLinearPremultipliedBGRA: pixels,
            width: width, height: height) else { return nil }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }
    #endif

    func draw(in view: MTKView) {
        guard bounds.width > 0, bounds.height > 0, let drawable = currentDrawable,
              let command = shared.queue.makeCommandBuffer() else { return }
        let target = drawable.texture
        if displayAttachments?.width != target.width || displayAttachments?.height != target.height {
            displayAttachments = makeAttachments(width: target.width, height: target.height)
        }
        guard let attachments = displayAttachments else { return }
        let descriptor = renderPass(resolvingInto: target, attachments: attachments)
        guard encode(descriptor: descriptor, command: command) else { return }
        let generation = artworkGeneration
        let renderedProgress = uniforms.progress
        command.addCompletedHandler { [weak self] completed in
            guard completed.status == .completed else { return }
            Task { @MainActor [weak self] in
                guard let self, artworkGeneration == generation else { return }
                lastRenderedProgress = renderedProgress
                if !hasRenderedFrame {
                    hasRenderedFrame = true
                    didRenderFirstFrame?()
                }
            }
        }
        command.present(drawable)
        command.commit()
    }
}
#endif
