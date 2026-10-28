#if SUMI
import CoreHaptics
import AVFAudio
import UIKit

/// One retained waveform is modulated during a real gesture. No haptic work is
/// attached to page landing, image loading, scrub animation, or display refresh.
@MainActor
final class SumiPaperHaptics: NSObject {
    private var engine: CHHapticEngine?
    private var motionPlayer: (any CHHapticAdvancedPatternPlayer)?
    private var engineReady = false
    private var engineStarting = false
    private var engineGeneration = UUID()
    private var clock: CADisplayLink?
    private var releaseTail: Task<Void, Never>?
    private var travel: CGFloat = 0
    private var lastContactTravel: CGFloat = 0
    private var lastContactTime: CFTimeInterval = 0
    private var active = false
    private var usingCore = false
    private var progress: CGFloat = 0
    private var velocity: CGFloat = 0
    private var distance: CGFloat = 1
    private var lastMovement: CFTimeInterval = 0
    private var lastTick: CFTimeInterval = 0
    private var lastProgressSample: CFTimeInterval = 0
    private var lastParameterUpdate: CFTimeInterval = 0
    private var suppliedVelocity: CGFloat = 0
    private var derivedVelocity: CGFloat = 0
    private var intensity: Float = 0
    private let touchFeedback = SumiPaperTouchFeedback()
    private var nativeContactCount = 0
    private let inputMode: String
    private let writesDiagnostics: Bool
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let instanceID = UUID().uuidString
    private var gestureID = UUID().uuidString
    private var maximumProgress: CGFloat = 0
    private var maximumVelocity: CGFloat = 0
    private var maximumSuppliedVelocity: CGFloat = 0
    private var maximumDerivedVelocity: CGFloat = 0
    private var gestureUpdateCount = 0
    private var motionUpdateCount = 0
    private var nonzeroMotionUpdateCount = 0
    private var gestureDrivenMotionUpdateCount = 0
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
    func prepare(in view: UIView? = nil) {
        touchFeedback.prepare(in: view)
        guard UIApplication.shared.applicationState == .active, !UIAccessibility.isReduceMotionEnabled,
              supportsHaptics,
              !engineReady, !engineStarting else { return }
        do {
            if engine == nil {
                let engine = try CHHapticEngine(audioSession: nil)
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
                    // on the fallback path. Finger-down itself stays silent.
                    if engineReady, active, !usingCore, !UIAccessibility.isReduceMotionEnabled {
                        _ = startCoreMotion()
                    }
                    record("engineStartCompleted")
                }
            }
        } catch {
            recordError(error, stage: "prepare")
            engineStopped(reset: true)
        }
    }

    func begin(distance: CGFloat, visible: Bool, location: CGPoint? = nil) {
        cancel()
        guard visible, UIApplication.shared.applicationState == .active else { return }
        self.distance = max(1, distance)
        gestureID = UUID().uuidString
        maximumProgress = 0; maximumVelocity = 0
        maximumSuppliedVelocity = 0; maximumDerivedVelocity = 0
        gestureUpdateCount = 0; motionUpdateCount = 0
        nonzeroMotionUpdateCount = 0; gestureDrivenMotionUpdateCount = 0
        maximumMotionIntensity = 0; maximumOutputIntensity = 0
        fallbackUsed = false; coreStartedForGesture = false; lastError = nil
        nativeContactCount = 0
        touchFeedback.update(location: location)
        progress = 0; velocity = 0; intensity = 0
        travel = 0; lastContactTravel = 0; lastContactTime = 0
        suppliedVelocity = 0; derivedVelocity = 0
        lastMovement = CACurrentMediaTime(); lastTick = lastMovement
        lastProgressSample = lastMovement
        lastParameterUpdate = 0
        active = true
        prepare()
        // A pan has already crossed the touch threshold. Keep its first
        // contact on the display-attached path that worked in Build 22,
        // independently of the custom engine and its asynchronous callbacks.
        if touchFeedback.play(releasing: false, intensity: 0.6) {
            nativeContactCount += 1
            maximumOutputIntensity = 0.6
        }
        _ = startCoreMotion()
        record("begin")
    }

    @discardableResult private func startCoreMotion() -> Bool {
        guard active, engineReady, !UIAccessibility.isReduceMotionEnabled,
              engine?.isMutedForHaptics == false, let motionPlayer else { return false }
        do {
            // The cached pattern starts silent. Start playback first, then
            // send live control parameters to that running player.
            try motionPlayer.start(atTime: CHHapticTimeImmediate)
            usingCore = true
            coreStartedForGesture = true
            clock?.invalidate()
            let clock = CADisplayLink(target: self, selector: #selector(tick(_:)))
            clock.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            clock.add(to: .main, forMode: .common)
            self.clock = clock
            sendMotion(now: CACurrentMediaTime(), fromGesture: false, force: true)
            return true
        } catch {
            usingCore = false; engineReady = false
            try? motionPlayer.stop(atTime: CHHapticTimeImmediate)
            recordError(error, stage: "motionStart")
            return false
        }
    }

    func update(progress: CGFloat, velocity: CGFloat, location: CGPoint? = nil) {
        guard active, progress.isFinite else { return }
        touchFeedback.update(location: location)
        let now = CACurrentMediaTime()
        let next = min(1, max(0, progress))
        let delta = next - self.progress
        travel += abs(delta) * distance
        let elapsed = max(1.0 / 240, now - lastProgressSample)
        suppliedVelocity = velocity.isFinite ? velocity : 0
        // Keep slow drags measurable at 120 Hz; filtering each small sample
        // would discard real motion when the recognizer supplies zero speed.
        if abs(delta) > 0.000001 {
            lastMovement = now
            derivedVelocity = delta * distance / elapsed
        } else if now - lastMovement > 0.06 {
            derivedVelocity = 0
        }
        lastProgressSample = now
        self.progress = next
        // Device and remote input can move the leaf while reporting zero pan
        // velocity. Recover its real speed from measured point displacement.
        self.velocity = abs(suppliedVelocity) > 1 ? suppliedVelocity : derivedVelocity
        gestureUpdateCount += 1
        maximumProgress = max(maximumProgress, next)
        maximumVelocity = max(maximumVelocity, abs(self.velocity))
        maximumSuppliedVelocity = max(maximumSuppliedVelocity, abs(suppliedVelocity))
        maximumDerivedVelocity = max(maximumDerivedVelocity, abs(derivedVelocity))
        // Short gestures must reach the motor even if there is no intervening
        // display-link tick. The same throttle also covers clock-driven decay.
        sendMotion(now: now, fromGesture: true)
        guard active, UIApplication.shared.applicationState == .active else { return }
        // Fine, soft contacts anchor the paper fibres to the reader display.
        // They accompany continuous resistance, and remain available while a
        // cold/interrupted engine warms up. No hard release impact or page-landing pulse.
        if travel >= 24, travel - lastContactTravel >= 24, now - lastContactTime >= 0.05 {
            let friction = SumiPaperHapticPolicy.motion(progress: next, velocity: self.velocity,
                distance: distance, idleFor: 0, travel: travel)
            let strength = min(0.58, 0.42 + friction.intensity * 0.28)
            lastContactTravel = travel
            lastContactTime = now
            if touchFeedback.play(releasing: false, intensity: strength) {
                nativeContactCount += 1
                if !usingCore { fallbackUsed = true }
                maximumOutputIntensity = max(maximumOutputIntensity, strength)
            }
        }
    }

    func release(velocity _: CGFloat, cancelled: Bool = false) {
        guard active else { return }
        active = false
        clock?.invalidate(); clock = nil
        guard UIApplication.shared.applicationState == .active else { stopPlayback(); return }
        // Paper friction relaxes at finger-up, without the former medium impact.
        // No haptic is attached to the page landing or programmatic scrub flip.
        if usingCore, engineReady, intensity > 0.01, !cancelled {
            do {
                let curve = CHHapticParameterCurve(parameterID: .hapticIntensityControl,
                    controlPoints: [.init(relativeTime: 0, value: intensity),
                                    .init(relativeTime: 0.035, value: 0)], relativeTime: 0)
                try motionPlayer?.scheduleParameterCurve(curve, atTime: CHHapticTimeImmediate)
                let gesture = gestureID
                releaseTail = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
                    guard let self, gestureID == gesture, !active else { return }
                    stopPlayback()
                }
            } catch {
                recordError(error, stage: "frictionRelease")
                stopPlayback()
            }
        } else { stopPlayback() }
        record(cancelled ? "endCancelled" : "end")
    }

    /// Cancellation/rotation/closing is silent, and stops even a paused leaf.
    func cancel() {
        let wasActive = active
        stopPlayback()
        if wasActive { record("cancel") }
    }

    private func stopPlayback() {
        active = false
        stopCorePlayback()
    }

    /// Core Haptics can reset or reject live controls without ending the pan.
    /// Its lifecycle must never cancel the native feedback for that gesture.
    private func stopCorePlayback() {
        releaseTail?.cancel(); releaseTail = nil
        usingCore = false
        clock?.invalidate(); clock = nil
        try? motionPlayer?.stop(atTime: CHHapticTimeImmediate)
        intensity = 0
    }

    @objc func suspend() {
        cancel()
        engineGeneration = UUID()
        engineReady = false; engineStarting = false
        engine?.stop(completionHandler: nil)
    }

    @objc private func accessibilityChanged() { suspend() }

    private func engineStopped(reset: Bool, reason: Int? = nil) {
        stopCorePlayback()
        if UIApplication.shared.applicationState != .active { active = false }
        engineGeneration = UUID()
        engineReady = false; engineStarting = false
        if reset { motionPlayer = nil }
        record(reset ? "engineReset" : "engineStopped", stoppedReason: reason)
        // Restart only for the next real interaction, never during a system
        // interruption or while the app is backgrounded.
    }

    @objc private func tick(_ link: CADisplayLink) {
        sendMotion(now: CACurrentMediaTime(), fromGesture: false)
    }

    private func sendMotion(now: CFTimeInterval, fromGesture: Bool, force: Bool = false) {
        guard active, usingCore else { return }
        guard UIApplication.shared.applicationState == .active,
              !UIAccessibility.isReduceMotionEnabled else { cancel(); return }
        let sample = SumiPaperHapticPolicy.motion(progress: progress, velocity: velocity, distance: distance, idleFor: now - lastMovement, travel: travel)
        let firstMovement = sample.intensity > 0 && nonzeroMotionUpdateCount == 0
        guard force || firstMovement || now - lastParameterUpdate >= 1.0 / 60 else { return }
        let blend: Float = firstMovement ? 1 : Float(1 - exp(-max(0, now - lastTick) / 0.025))
        lastTick = now
        if now - lastMovement >= 0.07 { intensity = 0 }
        else { intensity += (sample.intensity - intensity) * blend }
        do {
            guard let motionPlayer else { return }
            try motionPlayer.sendParameters([
                .init(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0),
                .init(parameterID: .hapticSharpnessControl, value: sample.sharpness, relativeTime: 0)
            ], atTime: CHHapticTimeImmediate)
            lastParameterUpdate = now
            motionUpdateCount += 1
            if intensity > 0 { nonzeroMotionUpdateCount += 1 }
            if fromGesture { gestureDrivenMotionUpdateCount += 1 }
            maximumMotionIntensity = max(maximumMotionIntensity, intensity)
            maximumOutputIntensity = max(maximumOutputIntensity, intensity)
        } catch {
            recordError(error, stage: "motionUpdate")
            stopCorePlayback()
            engineReady = false
        }
    }

    private func makePlayers(engine: CHHapticEngine) throws {
        let paper = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            .init(parameterID: .hapticIntensity, value: 1),
            .init(parameterID: .hapticSharpness, value: 0.25)
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
            "suppliedVelocity": Double(suppliedVelocity), "derivedVelocity": Double(derivedVelocity),
            "maximumSuppliedVelocity": Double(maximumSuppliedVelocity),
            "maximumDerivedVelocity": Double(maximumDerivedVelocity),
            "gestureUpdateCount": gestureUpdateCount, "motionUpdateCount": motionUpdateCount,
            "nonzeroMotionUpdateCount": nonzeroMotionUpdateCount,
            "gestureDrivenMotionUpdateCount": gestureDrivenMotionUpdateCount,
            "maximumMotionIntensity": maximumMotionIntensity, "maximumOutputIntensity": maximumOutputIntensity,
            "fallbackUsed": fallbackUsed
        ]
        snapshot["profile"] = "paperFriction-native-v3"
        snapshot["travelPoints"] = Double(travel)
        snapshot["nativeContactCount"] = nativeContactCount
        snapshot["nativeFeedbackAttachedToReader"] = touchFeedback.isAttached
        snapshot["audioHapticsAllowedDuringRecording"] = AVAudioSession.sharedInstance().allowHapticsAndSystemSoundsDuringRecording
        snapshot["audioCategory"] = AVAudioSession.sharedInstance().category.rawValue
        snapshot["edgePreparation"] = SumiPageEdgeMetadataCache.shared.status()
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
