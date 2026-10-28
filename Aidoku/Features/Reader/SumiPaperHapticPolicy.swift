#if SUMI
import Foundation

/// Paper resistance follows the finger, rather than firing at page boundaries.
enum SumiPaperHapticPolicy {
    struct Sample: Equatable {
        let intensity: Float
        let sharpness: Float
        static let silent = Sample(intensity: 0, sharpness: 0)
    }

    static let liftIntensity: Float = 0

    static func motion(progress: CGFloat, velocity: CGFloat, distance: CGFloat,
                       idleFor: TimeInterval, reducedMotion: Bool = false, travel: CGFloat? = nil) -> Sample {
        guard !reducedMotion, progress.isFinite, velocity.isFinite, distance.isFinite,
              idleFor.isFinite, distance > 0 else { return .silent }
        let position = min(1, max(0, Double(progress)))
        let speed = min(1, abs(Double(velocity)) / Double(distance) / 2.5)
        guard speed > 0.002, idleFor < 0.07 else { return .silent }
        let movement = sqrt(speed)
        let contact = sin(position * .pi)
        // Two spatial wavelengths imitate uneven paper fibres. Reversing or
        // pausing the finger changes the friction, not an independent buzz loop.
        let travelled = Double(travel ?? (progress * distance))
        let grain = 0.88 + 0.08 * sin(travelled * 0.17) + 0.04 * sin(travelled * 0.47)
        let idle = min(1, max(0, (0.07 - max(0, idleFor)) / 0.04))
        return Sample(intensity: Float((0.18 + 0.22 * contact + 0.10 * speed) * movement * idle * grain),
                      sharpness: Float(0.20 + 0.22 * speed + 0.06 * grain))
    }

    static func releaseIntensity(velocity: CGFloat, distance: CGFloat, cancelled: Bool) -> Float {
        // Finger-up uses a brief decay of the current friction, not an impact.
        0
    }
}
#endif
