@testable import Sumi
import Testing

struct HonbakoCoverCameraRequestsTests {
    @Test("Closing invalidates a start still queued behind capture configuration")
    func closeInvalidatesQueuedStart() {
        let requests = HonbakoCoverCameraRequests()
        let start = requests.issue(running: true)
        let close = requests.issue(running: false)
        #expect(!requests.isCurrent(start))
        #expect(requests.isCurrent(close))
        #expect(!requests.wantsRunning)
        #expect(requests.cancel(start) == nil)
        #expect(requests.isCurrent(close))
    }

    @Test("Canceling a pending camera start immediately withdraws its intent")
    func cancellationWithdrawsStart() throws {
        let requests = HonbakoCoverCameraRequests()
        let start = requests.issue(running: true)
        let stop = try #require(requests.cancel(start))
        #expect(!requests.wantsRunning)
        #expect(!requests.isCurrent(start))
        #expect(requests.isCurrent(stop))
    }

    @Test("A stale cancellation or queued stop cannot override a newer foreground start")
    func staleCancellationCannotStopNewReader() throws {
        let requests = HonbakoCoverCameraRequests()
        let oldStart = requests.issue(running: true)
        let oldStop = try #require(requests.cancel(oldStart))
        let newStart = requests.issue(running: true)
        #expect(requests.cancel(oldStart) == nil)
        #expect(!requests.isCurrent(oldStop))
        #expect(requests.isCurrent(newStart))
        #expect(requests.wantsRunning)
    }
}
