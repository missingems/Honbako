@testable import Sumi
import Testing

@MainActor
@Suite(.serialized)
struct SumiLibraryReturnRefreshTests {
    @Test("Closing publishes fresh metadata without waiting for an unrelated cover preload")
    func returnDoesNotWaitForCoverCohort() async throws {
        let gate = ReturnRefreshGate()
        let store = SumiLibraryStore(searchSourceLoader: { [] }, coverPreparer: { _ in await gate.prepare() })
        let notificationRefresh = Task { await store.refresh() }
        #expect(await gate.waitForCall(1))
        // The old snapshot is held behind artwork. Closing must publish its
        // post-save database read independently, without invoking that loader.
        let refreshed = await store.refreshForReturn()
        let returnedLibrary = store.library
        await gate.release(1)
        await notificationRefresh.value
        #expect(refreshed)
        #expect(await gate.callCount == 1)
        #expect(store.library == returnedLibrary, "The earlier held refresh cannot overwrite the newer return snapshot")
    }

    @Test("Canceling before a close refresh cannot begin cover work")
    func cancellationStopsReturnRefresh() async throws {
        let gate = ReturnRefreshGate()
        let store = SumiLibraryStore(searchSourceLoader: { [] }, coverPreparer: { _ in await gate.prepare() })
        let returning = Task { await store.refreshForReturn() }
        returning.cancel()
        #expect(await returning.value == false)
        #expect(await gate.callCount == 0)
    }

}

private actor ReturnRefreshGate {
    private(set) var callCount = 0
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]

    func prepare() async {
        callCount += 1
        let call = callCount
        if call == 1 { await withCheckedContinuation { continuations[call] = $0 } }
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
