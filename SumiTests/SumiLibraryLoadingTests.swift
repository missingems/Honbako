@testable import Sumi
import AidokuRunner
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct SumiLibraryLoadingTests {
    @Test("A newly created store is unresolved before any task starts")
    func startsLoading() {
        let store = SumiLibraryStore(searchSourceLoader: { [] })
        #expect(store.loadState == .loading)
        #expect(store.library.isEmpty)
    }

    @Test("Only a completed query can establish a genuinely empty library")
    func emptyRequiresSuccessfulSnapshot() async {
        let loader = LibrarySnapshotGate()
        var tutorialInstalls = 0
        let store = SumiLibraryStore(searchSourceLoader: { [] }, coverPreparer: { _ in },
            tutorialInstaller: { tutorialInstalls += 1 }, snapshotLoader: { try await loader.load() })
        let refresh = Task { await store.refresh() }
        #expect(await loader.waitForCall(1))
        #expect(store.loadState == .loading)
        #expect(store.library.isEmpty)
        loader.finish(1, with: .success(.init(saved: [], recent: [])))
        await refresh.value
        #expect(store.loadState == .loaded)
        #expect(store.library.isEmpty)
        #expect(tutorialInstalls == 0, "Injected snapshots never install into the real library")
    }

    @Test("An initial failure remains distinguishable from empty and can be retried")
    func initialErrorThenRetry() async {
        let loader = LibrarySnapshotGate()
        let store = makeStore(loader)
        let first = Task { await store.refresh() }
        #expect(await loader.waitForCall(1))
        loader.finish(1, with: .failure(URLError(.cannotOpenFile)))
        await first.value
        guard case .failed(let message) = store.loadState else {
            Issue.record("A failed initial load must not become loaded/empty")
            return
        }
        #expect(!message.isEmpty)
        let retry = Task { await store.refresh() }
        #expect(await loader.waitForCall(2))
        #expect(store.loadState == .loading)
        let book = existingBook()
        loader.finish(2, with: .success(.init(saved: [book], recent: [])))
        await retry.value
        #expect(store.loadState == .loaded)
        #expect(store.library == [book])
    }

    @Test("A superseded initial empty query cannot expose the empty screen while a newer query is pending")
    func supersededEmptyWaitsForCurrentLoad() async {
        let loader = LibrarySnapshotGate()
        let store = makeStore(loader)
        let earlier = Task { await store.refresh() }
        #expect(await loader.waitForCall(1))
        let current = Task { await store.refresh() }
        #expect(await loader.waitForCall(2))
        loader.finish(1, with: .success(.init(saved: [], recent: [])))
        await earlier.value
        #expect(store.loadState == .loading)
        let book = existingBook()
        loader.finish(2, with: .success(.init(saved: [book], recent: [])))
        await current.value
        #expect(store.loadState == .loaded)
        #expect(store.library == [book])
    }

    @Test("Refreshing and later errors preserve an already published library")
    func refreshKeepsExistingBooksVisible() async {
        let loader = LibrarySnapshotGate()
        let store = makeStore(loader)
        let first = Task { await store.refresh() }
        #expect(await loader.waitForCall(1))
        let book = existingBook()
        loader.finish(1, with: .success(.init(saved: [book], recent: [])))
        await first.value
        let refresh = Task { await store.refresh() }
        #expect(await loader.waitForCall(2))
        #expect(store.loadState == .loaded)
        #expect(store.library == [book])
        loader.finish(2, with: .failure(URLError(.cannotOpenFile)))
        await refresh.value
        #expect(store.loadState == .loaded)
        #expect(store.library == [book])
        #expect(store.errorMessage != nil)
    }

    @Test("Canceling an initial query cannot establish an empty snapshot")
    func canceledInitialLoadRemainsUnresolved() async {
        let loader = LibrarySnapshotGate()
        let store = makeStore(loader)
        let refresh = Task { await store.refresh() }
        #expect(await loader.waitForCall(1))
        refresh.cancel()
        loader.finish(1, with: .success(.init(saved: [], recent: [])))
        await refresh.value
        #expect(store.loadState == .loading)
        #expect(store.library.isEmpty)
    }

    private func makeStore(_ loader: LibrarySnapshotGate) -> SumiLibraryStore {
        SumiLibraryStore(searchSourceLoader: { [] }, coverPreparer: { _ in },
            snapshotLoader: { try await loader.load() })
    }

    private func existingBook() -> SumiBook {
        SumiBook(manga: AidokuRunner.Manga(sourceKey: "loading-test", key: "existing", title: "Existing Book"),
            isInLibrary: true)
    }
}

@MainActor
private final class LibrarySnapshotGate {
    private var callCount = 0
    private var continuations: [Int: CheckedContinuation<SumiLibrarySnapshot, any Error>] = [:]

    func load() async throws -> SumiLibrarySnapshot {
        callCount += 1
        let call = callCount
        return try await withCheckedThrowingContinuation { continuations[call] = $0 }
    }

    func finish(_ call: Int, with result: Result<SumiLibrarySnapshot, any Error>) {
        continuations.removeValue(forKey: call)?.resume(with: result)
    }

    func waitForCall(_ count: Int) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while callCount < count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return callCount >= count
    }
}
