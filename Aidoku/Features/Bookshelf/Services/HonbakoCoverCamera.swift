#if SUMI
@preconcurrency import AVFoundation
import Foundation

/// Capture configuration and blocking start/stop calls stay on this queue.
/// No microphone, recording output, file writer, or sample-buffer delegate exists.
final class HonbakoCoverCamera: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Honbako.CoverDisplay.Camera", qos: .userInitiated)
    private let session = AVCaptureSession()
    private let requests = HonbakoCoverCameraRequests()
    private var configured = false

    func setRunning(_ running: Bool) async -> String {
        guard !Task.isCancelled else { return "stopped" }
        // Publish intent before entering the capture queue. A blocked older
        // start cannot supersede a close/background request waiting behind it.
        let request = requests.issue(running: running)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { [self] in
                    guard requests.isCurrent(request) else {
                        continuation.resume(returning: session.isRunning ? "running" : "stopped")
                        return
                    }
                    if !running {
                        if session.isRunning { session.stopRunning() }
                        continuation.resume(returning: "stopped")
                        return
                    }
                    guard configure() else {
                        continuation.resume(returning: "unavailable")
                        return
                    }
                    guard requests.isCurrent(request) else {
                        stopIfNoLongerWanted()
                        continuation.resume(returning: session.isRunning ? "running" : "stopped")
                        return
                    }
                    if !session.isRunning { session.startRunning() }
                    // startRunning can block. A hide/close arriving during it
                    // must stop the newly started session before this job ends.
                    stopIfNoLongerWanted()
                    continuation.resume(returning: session.isRunning ? "running" : "stopped")
                }
            }
        } onCancel: { [self] in
            // Cancel only this request. A stale task cannot cancel a newer
            // foreground start, and a canceled queued start never runs later.
            guard let stop = requests.cancel(request) else { return }
            queue.async { [self] in
                guard requests.isCurrent(stop) else { return }
                stopIfNoLongerWanted()
            }
        }
    }

    private func stopIfNoLongerWanted() {
        if !requests.wantsRunning, session.isRunning { session.stopRunning() }
    }

    private func configure() -> Bool {
        guard !configured else { return true }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.automaticallyConfiguresApplicationAudioSession = false
        if session.canSetSessionPreset(.low) { session.sessionPreset = .low }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        // An active video connection is needed for camera-capture accessories.
        // With no delegate, frames are discarded without entering app code.
        session.addOutput(output)
        configured = true
        return true
    }

    deinit {
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }
}
#endif
