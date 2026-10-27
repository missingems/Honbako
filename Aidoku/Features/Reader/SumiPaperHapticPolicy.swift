#if SUMI
import Foundation

/// Paper resistance follows the finger, rather than firing at page boundaries.
enum SumiPaperHapticPolicy {
    struct Sample: Equatable {
        let intensity: Float
        let sharpness: Float
        static let silent = Sample(intensity: 0, sharpness: 0)
    }

    static let liftIntensity: Float = 0.22

    static func motion(progress: CGFloat, velocity: CGFloat, distance: CGFloat,
                       idleFor: TimeInterval, reducedMotion: Bool = false) -> Sample {
        guard !reducedMotion, progress.isFinite, velocity.isFinite, distance.isFinite,
              idleFor.isFinite, distance > 0 else { return .silent }
        let position = min(1, max(0, Double(progress)))
        let speed = min(1, abs(Double(velocity)) / Double(distance) / 3)
        let movement = sqrt(speed)
        let bend = sin(position * .pi)
        // A held leaf becomes silent; stale recognizer velocity cannot leave
        // the motor buzzing while the reader pauses with a finger down.
        let idle = min(1, max(0, (0.14 - max(0, idleFor)) / 0.08))
        let grain = 0.92 + 0.08 * cos(position * .pi * 48)
        return Sample(intensity: Float((0.045 + 0.13 * bend + 0.15 * speed) * movement * idle * grain),
            sharpness: Float(0.06 + 0.18 * speed + 0.07 * bend))
    }

    static func releaseIntensity(velocity: CGFloat, distance: CGFloat, cancelled: Bool) -> Float {
        guard !cancelled else { return 0.24 }
        let speed = velocity.isFinite && distance.isFinite && distance > 0
            ? min(1, abs(Double(velocity)) / Double(distance) / 4) : 0
        return Float(0.35 + 0.12 * speed)
    }
}
#endif
