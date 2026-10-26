#if SUMI
import RealityKit
import UIKit

@MainActor
final class SumiBookEntity {
    let root = Entity()
    private let spine = Entity()
    private let front = Entity()
    private var frameParts: [Entity] = []
    let leafWidth: Float

    init(cover: UIImage?, spread: UIImage, paired: Bool) throws {
        let size = spread.size
        leafWidth = Float(size.width / max(1, size.height) / (paired ? 2 : 1))
        let paper = SimpleMaterial(color: UIColor(white: 0.94, alpha: 1), roughness: 0.9, isMetallic: false)
        let board = SimpleMaterial(color: UIColor(white: 0.16, alpha: 1), roughness: 0.8, isMetallic: false)
        let left = paired ? Self.half(spread, right: false) : Self.blank(size: spread.size)
        let right = paired ? Self.half(spread, right: true) : spread
        root.addChild(frameBox(width: leafWidth, depth: 0.008, z: -0.016, material: board))
        root.addChild(frameBox(width: leafWidth * 0.994, depth: 0.02, z: -0.002, material: paper))
        root.addChild(try face(right, z: 0.009))
        root.addChild(spine)
        let binding = ModelEntity(mesh: .generateBox(width: 0.022, height: 1, depth: 0.008, cornerRadius: 0.002), materials: [board])
        binding.position = [0.011, 0, 0.012]
        spine.addChild(binding)
        frameParts.append(binding)
        front.position = [0, 0, 0.016]
        spine.addChild(front)
        front.addChild(frameBox(width: leafWidth, depth: 0.008, z: 0, material: board))
        front.addChild(try face(cover ?? right, z: 0.0045))
        let inside = try face(left, z: -0.0045)
        inside.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        front.addChild(inside)
    }

    func update(progress: CGFloat, closedAspect: CGFloat) {
        let value = Float(min(1, max(0, progress)))
        let halfAngle = SumiBookMotion.coverAngle(progress: progress) / 2
        spine.orientation = simd_quatf(angle: halfAngle, axis: [0, 1, 0])
        front.orientation = simd_quatf(angle: halfAngle, axis: [0, 1, 0])
        // Flatten the binding's depth at handoff so the left and right artwork
        // meet at exactly the same centre line as the native reader.
        front.position.z = 0.016 * (1 - value)
        root.scale.x = Float(closedAspect) / max(0.01, leafWidth) * (1 - value) + value
        // Only physical boards, page thickness, and the binding fade away.
        // The printed faces stay opaque, as Mooligan's content face does.
        let fade = min(1, value / 0.85)
        let opacity = 1 - fade * fade * (3 - 2 * fade)
        for part in frameParts { part.components.set(OpacityComponent(opacity: opacity)) }
    }

    private func frameBox(width: Float, depth: Float, z: Float, material: SimpleMaterial) -> ModelEntity {
        let entity = box(width: width, depth: depth, z: z, material: material)
        frameParts.append(entity)
        return entity
    }

    private func box(width: Float, depth: Float, z: Float, material: SimpleMaterial) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateBox(width: width, height: 1, depth: depth, cornerRadius: 0.003), materials: [material])
        entity.position = [leafWidth / 2, 0, z]
        return entity
    }

    private func face(_ image: UIImage, z: Float) throws -> ModelEntity {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let width = min(1536, image.size.width * image.scale)
        let size = CGSize(width: width, height: width * image.size.height / max(1, image.size.width))
        let raster = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let cgImage = raster.cgImage else { throw CocoaError(.fileReadCorruptFile) }
        let texture = try TextureResource.generate(from: cgImage, options: .init(semantic: .color))
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: .init(texture))
        material.faceCulling = .back
        let entity = ModelEntity(mesh: .generatePlane(width: leafWidth, height: 1, cornerRadius: 0), materials: [material])
        entity.position = [leafWidth / 2, 0, z]
        return entity
    }

    private static func half(_ image: UIImage, right: Bool) -> UIImage {
        guard let cg = image.cgImage,
              let crop = cg.cropping(to: CGRect(x: right ? cg.width / 2 : 0, y: 0, width: cg.width / 2, height: cg.height)) else { return image }
        return UIImage(cgImage: crop, scale: image.scale, orientation: .up)
    }

    private static func blank(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            SumiPaperSurface.backgroundColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
#endif
