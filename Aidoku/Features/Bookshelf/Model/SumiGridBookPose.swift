#if SUMI
import simd
import UIKit

/// Stable closed-book geometry shared by the grid and its pickup transition.
struct SumiGridBookPose: Equatable {
    static let coverAspect: Float = 0.68
    static let canvasAspect: CGFloat = 0.76
    static let cameraHalfHeight: Float = 0.57
    static let canvasHeight: Float = cameraHalfHeight * 2
    let pitch: Float
    let yaw: Float
    let roll: Float

    init(seed _: UInt64) {
        pitch = 0
        yaw = 12 * .pi / 180
        roll = 0
    }

    func orientation(progress: CGFloat) -> simd_quatf {
        simd_slerp(orientation, simd_quatf(angle: 0, axis: [0, 1, 0]), Float(min(1, max(0, progress))))
    }

    var orientation: simd_quatf {
        simd_quatf(angle: roll, axis: [0, 0, 1])
            * simd_quatf(angle: yaw, axis: [0, 1, 0])
            * simd_quatf(angle: pitch, axis: [1, 0, 0])
    }

    /// The book occupies a finite inset of its transparent render canvas.
    /// Returning to that same canvas avoids moving a tile when its image loads.
    var normalizedRenderingFrame: CGRect {
        var minimum = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        for x in [-Self.coverAspect / 2, Self.coverAspect / 2] {
            for y: Float in [-0.5, 0.5] {
                for z: Float in [-0.02, 0.025] {
                    let point = orientation.act([x, y, z])
                    minimum = simd_min(minimum, [point.x, point.y])
                    maximum = simd_max(maximum, [point.x, point.y])
                }
            }
        }
        let height = Self.cameraHalfHeight * 2
        let width = height * Float(Self.canvasAspect)
        return CGRect(x: CGFloat(0.5 + minimum.x / width),
                      y: CGFloat(0.5 - maximum.y / height),
                      width: CGFloat((maximum.x - minimum.x) / width),
                      height: CGFloat((maximum.y - minimum.y) / height))
    }
}
#endif
