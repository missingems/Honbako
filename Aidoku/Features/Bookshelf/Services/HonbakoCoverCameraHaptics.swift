#if SUMI
@preconcurrency import AVFAudio
import Foundation

/// Confined to the cover capture queue. Opt into recording-time haptics without
/// activating audio, changing its category, or adding microphone capture.
final class HonbakoCoverCameraHaptics: @unchecked Sendable {
    private var previousValue: Bool?

    func allow() {
        let audio = AVAudioSession.sharedInstance()
        if previousValue == nil { previousValue = audio.allowHapticsAndSystemSoundsDuringRecording }
        do {
            if !audio.allowHapticsAndSystemSoundsDuringRecording {
                try audio.setAllowHapticsAndSystemSoundsDuringRecording(true)
            }
            record("allowed", error: nil)
        } catch { record("allowFailed", error: error) }
    }

    func restore() {
        guard let previousValue else { return }
        self.previousValue = nil
        let audio = AVAudioSession.sharedInstance()
        do {
            if audio.allowHapticsAndSystemSoundsDuringRecording != previousValue {
                try audio.setAllowHapticsAndSystemSoundsDuringRecording(previousValue)
            }
            record("restored", error: nil)
        } catch { record("restoreFailed", error: error) }
    }

    private func record(_ event: String, error: Error?) {
        guard Bundle.main.object(forInfoDictionaryKey: "HonbakoPersonalFeatures") as? String == "YES" else { return }
        let audio = AVAudioSession.sharedInstance()
        var state: [String: Any] = ["event": event, "timestamp": Date.now.ISO8601Format(),
            "allowsRecordingHaptics": audio.allowHapticsAndSystemSoundsDuringRecording,
            "audioCategory": audio.category.rawValue]
        if let error {
            let error = error as NSError
            state["error"] = ["domain": error.domain, "code": error.code, "description": error.localizedDescription]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) else { return }
        try? data.write(to: URL.documentsDirectory.appending(path: "HonbakoCoverCameraHapticStatus.json"), options: .atomic)
    }
}
#endif
