#if SUMI
import CoreHaptics
import UIKit

/// One retained waveform is modulated during a real gesture. No haptic work is
/// attached to page landing, image loading, scrub animation, or display refresh.
@MainActor
final class SumiPaperHaptics: NSObject {
    private var engine: CHHapticEngine?
    private var motionPlayer: (any CHHapticAdvancedPatternPlayer)?
    private var liftPlayer: (any CHHapticPatternPlayer)?
    private var releasePlayer: (any CHHapticPatternPlayer)?
    private var engineReady = false
    private var engineStarting = false
    private var engineGeneration = UUID()
    private var clock: CADisplayLink?
    private var active = false
    private var usingCore = false
    private var progress: CGFloat = 0
    private var velocity: CGFloat = 0
    private var distance: CGFloat = 1
    private var lastMovement: CFTimeInterval = 0
    private var lastTick: CFTimeInterval = 0
    private var intensity: Float = 0
    private let fallback = UIImpactFeedbackGenerator(style: .soft)

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(suspend),
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accessibilityChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    /// Warm the engine before a touch, without changing the audio session or
    /// overriding any system haptic/mute policy. Unsupported devices use UIKit.
    func prepare() {
        fallback.prepare()
        guard UIApplication.shared.applicationState == .active, !UIAccessibility.isReduceMotionEnabled,
              CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              !engineReady, !engineStarting else { return }
        do {
            if engine == nil {
                let engine = try CHHapticEngine()
                engine.playsHapticsOnly = true
                engine.isAutoShutdownEnabled = true
                engine.stoppedHandler = { [weak self] _ in
                    Task { @MainActor [weak self] in self?.engineStopped(reset: false) }
                }
                engine.resetHandler = { [weak self] in
                    Task { @MainActor [weak self] in self?.engineStopped(reset: true) }
                }
                self.engine = engine
            }
            guard let engine else { return }
            if motionPlayer == nil { try makePlayers(engine: engine) }
            engineStarting = true
            let generation = engineGeneration
            engine.start { [weak self] error in
                let succeeded = error == nil
                Task { @MainActor [weak self] in
                    guard let self, engineGeneration == generation else { return }
                    engineStarting = false
                    engineReady = succeeded && UIApplication.shared.applicationState == .active
                }
            }
        } catch { engineStopped(reset: true) }
    }

    func begin(distance: CGFloat, visible: Bool) {
        cancel()
        guard visible, UIApplication.shared.applicationState == .active else { return }
        self.distance = max(1, distance)
        progress = 0; velocity = 0; intensity = 0
        lastMovement = CACurrentMediaTime(); lastTick = lastMovement
        active = true
        prepare()
        usingCore = engineReady && !UIAccessibility.isReduceMotionEnabled
        if usingCore {
            do {
                try motionPlayer?.sendParameters([.init(parameterID: .hapticIntensityControl, value: 0, relativeTime: 0)], atTime: CHHapticTimeImmediate)
                try motionPlayer?.start(atTime: CHHapticTimeImmediate)
                try liftPlayer?.start(atTime: CHHapticTimeImmediate)
                let clock = CADisplayLink(target: self, selector: #selector(tick(_:)))
                clock.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
                clock.add(to: .main, forMode: .common)
                self.clock = clock
            } catch {
                usingCore = false
                try? motionPlayer?.stop(atTime: CHHapticTimeImmediate)
                fallback.impactOccurred(intensity: CGFloat(SumiPaperHapticPolicy.liftIntensity))
            }
        } else { fallback.impactOccurred(intensity: CGFloat(SumiPaperHapticPolicy.liftIntensity)) }
    }

    func update(progress: CGFloat, velocity: CGFloat) {
        guard active, progress.isFinite, velocity.isFinite else { return }
        let next = min(1, max(0, progress))
        if abs(next - self.progress) > 0.0005 { lastMovement = CACurrentMediaTime() }
        self.progress = next
        self.velocity = velocity
    }

    func release(velocity: CGFloat, cancelled: Bool = false) {
        guard active else { return }
        let wasCore = usingCore
        cancel()
        guard UIApplication.shared.applicationState == .active else { return }
        let strength = SumiPaperHapticPolicy.releaseIntensity(velocity: velocity, distance: distance, cancelled: cancelled)
        if wasCore, engineReady {
            do {
                try releasePlayer?.sendParameters([.init(parameterID: .hapticIntensityControl, value: strength, relativeTime: 0)], atTime: CHHapticTimeImmediate)
                try releasePlayer?.start(atTime: CHHapticTimeImmediate)
                try releasePlayer?.scheduleParameterCurve(CHHapticParameterCurve(parameterID: .hapticIntensityControl,
                    controlPoints: [.init(relativeTime: 0, value: strength),
                                    .init(relativeTime: 0.025, value: strength * 0.6),
                                    .init(relativeTime: 0.108, value: 0)], relativeTime: 0), atTime: CHHapticTimeImmediate)
                return
            } catch { engineReady = false }
        }
        fallback.impactOccurred(intensity: CGFloat(strength))
        fallback.prepare()
    }

    /// Cancellation/rotation/closing is silent, and stops even a paused leaf.
    func cancel() {
        active = false; usingCore = false
        clock?.invalidate(); clock = nil
        try? motionPlayer?.stop(atTime: CHHapticTimeImmediate)
        try? liftPlayer?.stop(atTime: CHHapticTimeImmediate)
        try? releasePlayer?.stop(atTime: CHHapticTimeImmediate)
        intensity = 0
    }

    @objc func suspend() {
        cancel()
        try? liftPlayer?.stop(atTime: CHHapticTimeImmediate)
        try? releasePlayer?.stop(atTime: CHHapticTimeImmediate)
        engineGeneration = UUID()
        engineReady = false; engineStarting = false
        engine?.stop(completionHandler: nil)
    }

    @objc private func accessibilityChanged() { suspend() }

    private func engineStopped(reset: Bool) {
        cancel()
        engineGeneration = UUID()
        engineReady = false; engineStarting = false
        if reset { motionPlayer = nil; liftPlayer = nil; releasePlayer = nil }
        // Restart only for the next real interaction, never during a system
        // interruption or while the app is backgrounded.
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard active, usingCore, UIApplication.shared.applicationState == .active,
              !UIAccessibility.isReduceMotionEnabled else { cancel(); return }
        let now = CACurrentMediaTime()
        let sample = SumiPaperHapticPolicy.motion(progress: progress, velocity: velocity, distance: distance, idleFor: now - lastMovement)
        let blend = Float(1 - exp(-max(0, now - lastTick) / 0.025))
        lastTick = now
        intensity += (sample.intensity - intensity) * blend
        do {
            try motionPlayer?.sendParameters([
                .init(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0),
                .init(parameterID: .hapticSharpnessControl, value: sample.sharpness, relativeTime: 0)
            ], atTime: CHHapticTimeImmediate)
        } catch { cancel(); engineReady = false }
    }

    private func makePlayers(engine: CHHapticEngine) throws {
        let paper = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            .init(parameterID: .hapticIntensity, value: 1),
            .init(parameterID: .hapticSharpness, value: 0)
        ], relativeTime: 0, duration: 10)
        let motion = try engine.makeAdvancedPlayer(with: .init(events: [paper], parameters: []))
        motion.loopEnabled = true
        motion.loopEnd = 10
        motionPlayer = motion
        liftPlayer = try engine.makePlayer(with: .init(events: [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                .init(parameterID: .hapticIntensity, value: SumiPaperHapticPolicy.liftIntensity),
                .init(parameterID: .hapticSharpness, value: 0.12)
            ], relativeTime: 0)
        ], parameters: []))
        // One small release, followed by a decaying paper tail. It begins at
        // finger-up and is never retriggered when the visual page lands.
        releasePlayer = try engine.makePlayer(with: .init(events: [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                .init(parameterID: .hapticIntensity, value: 1),
                .init(parameterID: .hapticSharpness, value: 0.13)
            ], relativeTime: 0),
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                .init(parameterID: .hapticIntensity, value: 0.28),
                .init(parameterID: .hapticSharpness, value: 0.04)
            ], relativeTime: 0.008, duration: 0.10)
        ], parameters: []))
    }
}
#endif
