#if SUMI
import Foundation

/// Paper resistance follows the finger, rather than firing at page boundaries.
enum SumiPaperHapticPolicy {
    struct Sample: Equatable {
        let intensity: Float
        let sharpness: Float
        static let silent = Sample(intensity: 0, sharpness: 0)
    }

    static let liftIntensity: Float = 0.42

    static func motion(progress: CGFloat, velocity: CGFloat, distance: CGFloat,
                       idleFor: TimeInterval, reducedMotion: Bool = false) -> Sample {
        guard !reducedMotion, progress.isFinite, velocity.isFinite, distance.isFinite,
              idleFor.isFinite, distance > 0 else { return .silent }
        let position = min(1, max(0, Double(progress)))
        let speed = min(1, abs(Double(velocity)) / Double(distance) / 3)
        let movement = pow(speed, 0.3)
        let bend = sin(position * .pi)
        // A held leaf becomes silent; stale recognizer velocity cannot leave
        // the motor buzzing while the reader pauses with a finger down.
        let idle = min(1, max(0, (0.14 - max(0, idleFor)) / 0.08))
        let grain = 0.86 + 0.14 * cos(position * .pi * 48)
        return Sample(intensity: Float((0.24 + 0.18 * bend + 0.18 * speed) * movement * idle * grain),
            sharpness: Float(0.14 + 0.22 * speed + 0.09 * bend))
    }

    static func releaseIntensity(velocity: CGFloat, distance: CGFloat, cancelled: Bool) -> Float {
        guard !cancelled else { return 0.48 }
        let speed = velocity.isFinite && distance.isFinite && distance > 0
            ? min(1, abs(Double(velocity)) / Double(distance) / 4) : 0
        return Float(0.64 + 0.12 * speed)
    }
}
#endif
