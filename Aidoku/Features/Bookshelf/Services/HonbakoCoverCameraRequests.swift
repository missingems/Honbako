#if SUMI
import Foundation

/// This lock protects intent only; camera calls never hold it. All capture
/// objects remain confined to HonbakoCoverCamera's serial queue.
final class HonbakoCoverCameraRequests: @unchecked Sendable {
    struct Request: Equatable, Sendable {
        let id: UUID
        let running: Bool
    }

    private let lock = NSLock()
    private var latest = Request(id: UUID(), running: false)

    func issue(running: Bool) -> Request {
        lock.lock()
        defer { lock.unlock() }
        let request = Request(id: UUID(), running: running)
        latest = request
        return request
    }

    func isCurrent(_ request: Request) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return latest == request
    }

    var wantsRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return latest.running
    }

    func cancel(_ request: Request) -> Request? {
        lock.lock()
        defer { lock.unlock() }
        guard latest == request else { return nil }
        let stop = Request(id: UUID(), running: false)
        latest = stop
        return stop
    }
}
#endif
