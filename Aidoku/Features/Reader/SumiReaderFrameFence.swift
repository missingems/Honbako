#if SUMI
import UIKit

/// A bounded wait for UIKit to submit the destination behind an opaque handoff.
@MainActor
final class SumiReaderFrameFence: NSObject {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var link: CADisplayLink?
    private var timeout: Task<Void, Never>?
    private var remaining = 2
    private var finished = false

    static func wait() async -> Bool {
        let fence = SumiReaderFrameFence()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                fence.continuation = continuation
                if Task.isCancelled { fence.finish(false) }
                else { fence.start() }
            }
        } onCancel: {
            Task { @MainActor in fence.finish(false) }
        }
    }

    private func start() {
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        self.link = link
        link.add(to: .main, forMode: .common)
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.finish(false)
        }
    }

    @objc private func frame(_ link: CADisplayLink) {
        remaining -= 1
        if remaining == 0 { finish(true) }
    }

    private func finish(_ rendered: Bool) {
        guard !finished else { return }
        finished = true
        link?.invalidate(); link = nil
        timeout?.cancel(); timeout = nil
        let continuation = continuation; self.continuation = nil
        continuation?.resume(returning: rendered)
    }
}
#endif
