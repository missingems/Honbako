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
    private var cancelledReleasePlayer: (any CHHapticPatternPlayer)?
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
    private let inputMode: String
    private let writesDiagnostics: Bool
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let instanceID = UUID().uuidString
    private var gestureID = UUID().uuidString
    private var maximumProgress: CGFloat = 0
    private var maximumVelocity: CGFloat = 0
    private var maximumMotionIntensity: Float = 0
    private var maximumOutputIntensity: Float = 0
    private var fallbackUsed = false
    private var coreStartedForGesture = false
    private var lastError: [String: Any]?
    private static var diagnosticEvents: [[String: Any]] = []

    init(inputMode: String = "page", writesDiagnostics: Bool = HonbakoProStore.personalFeaturesEnabled) {
        self.inputMode = inputMode
        self.writesDiagnostics = writesDiagnostics
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
              supportsHaptics,
              !engineReady, !engineStarting else { return }
        do {
            if engine == nil {
                let engine = try CHHapticEngine()
                engine.playsHapticsOnly = true
                engine.isAutoShutdownEnabled = true
                engine.stoppedHandler = { [weak self] reason in
                    let code = reason.rawValue
                    Task { @MainActor [weak self] in self?.engineStopped(reset: false, reason: code) }
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
                let failure = error.map { $0 as NSError }
                Task { @MainActor [weak self] in
                    guard let self, engineGeneration == generation else { return }
                    engineStarting = false
                    engineReady = succeeded && UIApplication.shared.applicationState == .active
                    if let failure { recordError(failure, stage: "engineStart") }
                    // Engine warmup may finish just after finger-down. Promote
                    // this same gesture instead of leaving its entire motion
                    // on the fallback path. The lift already played once.
                    if engineReady, active, !usingCore, !UIAccessibility.isReduceMotionEnabled {
                        _ = startCoreMotion(playLift: false)
                    }
                    record("engineStartCompleted")
                }
            }
        } catch {
            recordError(error, stage: "prepare")
            engineStopped(reset: true)
        }
    }

    func begin(distance: CGFloat, visible: Bool) {
        cancel()
        guard visible, UIApplication.shared.applicationState == .active else { return }
        self.distance = max(1, distance)
        gestureID = UUID().uuidString
        maximumProgress = 0; maximumVelocity = 0
        maximumMotionIntensity = 0; maximumOutputIntensity = 0
        fallbackUsed = false; coreStartedForGesture = false; lastError = nil
        progress = 0; velocity = 0; intensity = 0
        lastMovement = CACurrentMediaTime(); lastTick = lastMovement
        active = true
        prepare()
        if !startCoreMotion(playLift: true) { playFallback(SumiPaperHapticPolicy.liftIntensity) }
        maximumOutputIntensity = SumiPaperHapticPolicy.liftIntensity
        record("begin")
    }

    @discardableResult private func startCoreMotion(playLift: Bool) -> Bool {
        guard active, engineReady, !UIAccessibility.isReduceMotionEnabled,
              engine?.isMutedForHaptics == false, let motionPlayer, let liftPlayer else { return false }
        do {
            // The cached pattern starts silent. Start playback first, then
            // send live control parameters to that running player.
            try motionPlayer.start(atTime: CHHapticTimeImmediate)
            if playLift { try liftPlayer.start(atTime: CHHapticTimeImmediate) }
            usingCore = true
            coreStartedForGesture = true
            clock?.invalidate()
            let clock = CADisplayLink(target: self, selector: #selector(tick(_:)))
            clock.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            clock.add(to: .main, forMode: .common)
            self.clock = clock
            return true
        } catch {
            usingCore = false; engineReady = false
            try? motionPlayer.stop(atTime: CHHapticTimeImmediate)
            recordError(error, stage: "motionStart")
            return false
        }
    }

    func update(progress: CGFloat, velocity: CGFloat) {
        guard active, progress.isFinite, velocity.isFinite else { return }
        let next = min(1, max(0, progress))
        if abs(next - self.progress) > 0.0005 { lastMovement = CACurrentMediaTime() }
        self.progress = next
        self.velocity = velocity
        maximumProgress = max(maximumProgress, next)
        maximumVelocity = max(maximumVelocity, abs(velocity))
    }

    func release(velocity: CGFloat, cancelled: Bool = false) {
        guard active else { return }
        let wasCore = usingCore
        stopPlayback()
        defer { record(cancelled ? "endCancelled" : "end") }
        guard UIApplication.shared.applicationState == .active else { return }
        let releaseVelocity = CACurrentMediaTime() - lastMovement > 0.12 ? 0 : velocity
        let strength = SumiPaperHapticPolicy.releaseIntensity(velocity: releaseVelocity, distance: distance, cancelled: cancelled)
        if wasCore, engineReady {
            do {
                // Fixed event intensities make the finger-up perceptible even
                // on an engine that resets player controls between starts.
                let player = cancelled ? cancelledReleasePlayer : releasePlayer
                try player?.start(atTime: CHHapticTimeImmediate)
                maximumOutputIntensity = max(maximumOutputIntensity, cancelled ? 0.48 : 0.72)
                return
            } catch {
                engineReady = false
                recordError(error, stage: "release")
            }
        }
        playFallback(strength)
        fallback.prepare()
    }

    /// Cancellation/rotation/closing is silent, and stops even a paused leaf.
    func cancel() {
        let wasActive = active
        stopPlayback()
        if wasActive { record("cancel") }
    }

    private func stopPlayback() {
        active = false; usingCore = false
        clock?.invalidate(); clock = nil
        try? motionPlayer?.stop(atTime: CHHapticTimeImmediate)
        try? liftPlayer?.stop(atTime: CHHapticTimeImmediate)
        try? releasePlayer?.stop(atTime: CHHapticTimeImmediate)
        try? cancelledReleasePlayer?.stop(atTime: CHHapticTimeImmediate)
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

    private func engineStopped(reset: Bool, reason: Int? = nil) {
        cancel()
        engineGeneration = UUID()
        engineReady = false; engineStarting = false
        if reset { motionPlayer = nil; liftPlayer = nil; releasePlayer = nil; cancelledReleasePlayer = nil }
        record(reset ? "engineReset" : "engineStopped", stoppedReason: reason)
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
        maximumMotionIntensity = max(maximumMotionIntensity, intensity)
        maximumOutputIntensity = max(maximumOutputIntensity, intensity)
        do {
            try motionPlayer?.sendParameters([
                .init(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0),
                .init(parameterID: .hapticSharpnessControl, value: sample.sharpness, relativeTime: 0)
            ], atTime: CHHapticTimeImmediate)
        } catch {
            recordError(error, stage: "motionUpdate")
            cancel(); engineReady = false
        }
    }

    private func makePlayers(engine: CHHapticEngine) throws {
        let paper = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            .init(parameterID: .hapticIntensity, value: 1),
            .init(parameterID: .hapticSharpness, value: 0.12)
        ], relativeTime: 0, duration: 10)
        let motion = try engine.makeAdvancedPlayer(with: .init(events: [paper], parameters: [
            .init(parameterID: .hapticIntensityControl, value: 0, relativeTime: 0)
        ]))
        motion.loopEnabled = true
        motion.loopEnd = 10
        motion.completionHandler = { [weak self] error in
            guard let error else { return }
            let failure = error as NSError
            Task { @MainActor [weak self] in
                self?.recordError(failure, stage: "motionCompletion")
                self?.engineStopped(reset: true)
            }
        }
        motionPlayer = motion
        liftPlayer = try engine.makePlayer(with: .init(events: [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                .init(parameterID: .hapticIntensity, value: SumiPaperHapticPolicy.liftIntensity),
                .init(parameterID: .hapticSharpness, value: 0.25)
            ], relativeTime: 0)
        ], parameters: []))
        // One small release, followed by a decaying paper tail. It begins at
        // finger-up and is never retriggered when the visual page lands.
        releasePlayer = try engine.makePlayer(with: releasePattern(strength: 0.72))
        cancelledReleasePlayer = try engine.makePlayer(with: releasePattern(strength: 0.48))
    }

    private func releasePattern(strength: Float) throws -> CHHapticPattern {
        try CHHapticPattern(events: [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                .init(parameterID: .hapticIntensity, value: strength),
                .init(parameterID: .hapticSharpness, value: 0.25)
            ], relativeTime: 0),
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                .init(parameterID: .hapticIntensity, value: strength * 0.4),
                .init(parameterID: .hapticSharpness, value: 0.12)
            ], relativeTime: 0.008, duration: 0.10)
        ], parameterCurves: [.init(parameterID: .hapticIntensityControl,
            controlPoints: [.init(relativeTime: 0, value: 1), .init(relativeTime: 0.025, value: 0.7),
                            .init(relativeTime: 0.108, value: 0)], relativeTime: 0)])
    }

    private func playFallback(_ strength: Float) {
        fallbackUsed = true
        maximumOutputIntensity = max(maximumOutputIntensity, strength)
        fallback.impactOccurred(intensity: CGFloat(strength))
    }

    private func recordError(_ error: Error, stage: String) {
        let error = error as NSError
        lastError = ["stage": stage, "domain": error.domain, "code": error.code,
                     "description": error.localizedDescription]
        record("error")
    }

    /// Owner-build evidence is local, bounded and written only at lifecycle
    /// boundaries. No page images, manga names, remote telemetry or frame I/O.
    private func record(_ event: String, stoppedReason: Int? = nil) {
        guard writesDiagnostics else { return }
        let state: String
        switch UIApplication.shared.applicationState {
        case .active: state = "active"
        case .inactive: state = "inactive"
        case .background: state = "background"
        @unknown default: state = "unknown"
        }
        var snapshot: [String: Any] = [
            "event": event, "timestamp": Date.now.ISO8601Format(), "inputMode": inputMode,
            "instanceID": instanceID, "gestureID": gestureID, "supportsHaptics": supportsHaptics,
            "engineReady": engineReady, "engineStarting": engineStarting,
            "appState": state, "reduceMotion": UIAccessibility.isReduceMotionEnabled,
            "active": active, "usingCore": usingCore, "coreStartedForGesture": coreStartedForGesture,
            "progress": Double(progress), "maximumProgress": Double(maximumProgress),
            "velocity": Double(velocity), "maximumVelocity": Double(maximumVelocity),
            "maximumMotionIntensity": maximumMotionIntensity, "maximumOutputIntensity": maximumOutputIntensity,
            "fallbackUsed": fallbackUsed
        ]
        snapshot["isMutedForHaptics"] = engine.map { $0.isMutedForHaptics as Any } ?? NSNull()
        snapshot["motionPlayerMuted"] = motionPlayer.map { $0.isMuted as Any } ?? NSNull()
        snapshot["error"] = lastError ?? [:]
        if let stoppedReason { snapshot["stoppedReason"] = stoppedReason }
        Self.diagnosticEvents.append(snapshot)
        if Self.diagnosticEvents.count > 32 { Self.diagnosticEvents.removeFirst(Self.diagnosticEvents.count - 32) }
        var document = snapshot
        document["schemaVersion"] = 1
        document["events"] = Self.diagnosticEvents
        guard let data = try? JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: URL.documentsDirectory.appendingPathComponent("HonbakoPaperHapticStatus.json"), options: .atomic)
    }
}
#endif
