@testable import Sumi
import Testing

@MainActor
@Suite(.serialized)
struct SumiLibraryReturnRefreshTests {
    @Test("A superseded close refresh retries until a post-save snapshot actually publishes")
    func supersededRefreshWaitsForPublication() async throws {
        let gate = ReturnRefreshGate()
        let store = SumiLibraryStore(searchSourceLoader: { [] }, coverPreparer: { _ in await gate.prepare() })
        let returning = Task { await store.refreshForReturn() }
        #expect(await gate.waitForCall(1))
        let notificationRefresh = Task { await store.refresh() }
        #expect(await gate.waitForCall(2))
        // The closing read finishes first, but its generation is obsolete and
        // the newer read is still held. Merely awaiting the first is unsafe.
        await gate.release(1)
        #expect(await gate.waitForCall(3), "A superseded read cannot claim that old library geometry is ready")
        // Release all earlier work before awaiting the result, even when the
        // assertion fails, so a database failure cannot strand a continuation.
        await gate.release(2)
        #expect(await returning.value)
        await notificationRefresh.value
    }

    @Test("Canceling the close cannot publish a held snapshot or begin another return refresh")
    func cancellationStopsReturnRefresh() async throws {
        let gate = ReturnRefreshGate()
        let store = SumiLibraryStore(searchSourceLoader: { [] }, coverPreparer: { _ in await gate.prepare() })
        let returning = Task { await store.refreshForReturn() }
        #expect(await gate.waitForCall(1))
        returning.cancel()
        await gate.release(1)
        #expect(await returning.value == false)
        #expect(await gate.callCount == 1)
    }
}

private actor ReturnRefreshGate {
    private(set) var callCount = 0
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]

    func prepare() async {
        callCount += 1
        let call = callCount
        if call <= 2 { await withCheckedContinuation { continuations[call] = $0 } }
    }

    func release(_ call: Int) { continuations.removeValue(forKey: call)?.resume() }

    func waitForCall(_ call: Int) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while callCount < call, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return callCount >= call
    }
}
