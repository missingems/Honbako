@testable import Sumi
import Foundation
import Testing

struct SumiPaperHapticPolicyTests {
    @Test("Paper resistance responds to drag speed and bend in either direction")
    func followsFingerMotion() {
        let slow = SumiPaperHapticPolicy.motion(progress: 0.5, velocity: 100, distance: 500, idleFor: 0)
        let fast = SumiPaperHapticPolicy.motion(progress: 0.5, velocity: 900, distance: 500, idleFor: 0)
        let reversed = SumiPaperHapticPolicy.motion(progress: 0.5, velocity: -900, distance: 500, idleFor: 0)
        let flat = SumiPaperHapticPolicy.motion(progress: 0, velocity: 900, distance: 500, idleFor: 0)
        #expect(fast.intensity > slow.intensity)
        #expect(fast.sharpness > slow.sharpness)
        #expect(fast == reversed)
        #expect(fast.intensity > flat.intensity)
    }

    @Test("Holding still fades the motor to silence despite stale recognizer velocity")
    func pausedPaperIsSilent() {
        let moving = SumiPaperHapticPolicy.motion(progress: 0.4, velocity: 700, distance: 450, idleFor: 0)
        let fading = SumiPaperHapticPolicy.motion(progress: 0.4, velocity: 700, distance: 450, idleFor: 0.10)
        let paused = SumiPaperHapticPolicy.motion(progress: 0.4, velocity: 700, distance: 450, idleFor: 0.15)
        #expect(moving.intensity > fading.intensity)
        #expect(fading.intensity > 0)
        #expect(paused.intensity == 0)
        #expect(SumiPaperHapticPolicy.motion(progress: 0.4, velocity: 0, distance: 450, idleFor: 0).intensity == 0)
    }

    @Test("Feedback follows relative page movement across narrow and wide displays")
    func geometryIndependentFeel() {
        let portrait = SumiPaperHapticPolicy.motion(progress: 0.5, velocity: 600, distance: 400, idleFor: 0)
        let landscape = SumiPaperHapticPolicy.motion(progress: 0.5, velocity: 1200, distance: 800, idleFor: 0)
        #expect(portrait == landscape)
    }

    @Test("Reduced Motion and invalid samples cannot start a continuous texture")
    func accessibleAndBounded() {
        #expect(SumiPaperHapticPolicy.motion(progress: 0.5, velocity: 500, distance: 450, idleFor: 0, reducedMotion: true) == .silent)
        for invalid in [CGFloat.nan, .infinity, -.infinity] {
            #expect(SumiPaperHapticPolicy.motion(progress: invalid, velocity: 500, distance: 450, idleFor: 0) == .silent)
            #expect(SumiPaperHapticPolicy.motion(progress: 0.5, velocity: invalid, distance: 450, idleFor: 0) == .silent)
        }
        #expect(SumiPaperHapticPolicy.motion(progress: 0.5, velocity: 500, distance: 0, idleFor: 0) == .silent)
        for progress in stride(from: CGFloat(-1), through: 2, by: 0.01) {
            let sample = SumiPaperHapticPolicy.motion(progress: progress, velocity: 100_000, distance: 1, idleFor: 0)
            #expect((0...0.61).contains(sample.intensity))
            #expect((0...0.46).contains(sample.sharpness))
        }
    }

    @Test("Finger-up is softer on a cancelled turn and stronger than the initial paper lift")
    func releaseIsDistinctFromLift() {
        let lift = SumiPaperHapticPolicy.liftIntensity
        let slow = SumiPaperHapticPolicy.releaseIntensity(velocity: 0, distance: 450, cancelled: false)
        let flick = SumiPaperHapticPolicy.releaseIntensity(velocity: 1800, distance: 450, cancelled: false)
        let cancelled = SumiPaperHapticPolicy.releaseIntensity(velocity: 1800, distance: 450, cancelled: true)
        #expect(lift < cancelled && cancelled < slow && slow < flick)
        #expect(flick <= 0.8)
    }

    @Test("Ordinary slow drags retain a noticeable paper body rather than only lift and release taps")
    func slowDragHasBody() {
        let sample = SumiPaperHapticPolicy.motion(progress: 0.5, velocity: 150, distance: 500, idleFor: 0)
        #expect(sample.intensity >= 0.2)
        #expect(SumiPaperHapticPolicy.liftIntensity >= 0.4)
        #expect(SumiPaperHapticPolicy.releaseIntensity(velocity: 500, distance: 500, cancelled: false) >= 0.65)
    }
}
