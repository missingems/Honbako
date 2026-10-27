@testable import Sumi
import Foundation
import Testing

struct SumiSourceSearchPipelineTests {
    @Test("A ready provider publishes before another provider's search returns")
    func independentProviders() async throws {
        let slow = Gate()
        let published = Recorder()
        let task = Task {
            await SumiSourceSearchPipeline.run(sourceKeys: ["slow", "fast"], fetch: { key in
                if key == "slow" { await slow.wait() }
                return key
            }, prepare: { await published.append($0) })
        }
        defer { task.cancel(); Task { await slow.release() } }
        try await wait { await published.values.contains("fast") }
        #expect(await published.values == ["fast"])
        await slow.release()
        await task.value
        #expect(Set(await published.values) == ["fast", "slow"])
    }

    @Test("Slow chapter preparation does not occupy a provider-fetch slot")
    func fetchingContinuesDuringPreparation() async throws {
        let preparation = Gate()
        let fetched = Recorder()
        let published = Recorder()
        let task = Task {
            await SumiSourceSearchPipeline.run(sourceKeys: ["first", "second"], maximumFetches: 1, fetch: { key in
                await fetched.append(key)
                return key
            }, prepare: { key in
                if key == "first" { await preparation.wait() }
                await published.append(key)
            })
        }
        defer { task.cancel(); Task { await preparation.release() } }
        try await wait { await published.values.contains("second") }
        #expect(await fetched.values == ["first", "second"])
        #expect(await published.values == ["second"])
        await preparation.release()
        await task.value
    }

    @Test("Cancelling a query drops even a source response that ignores cancellation")
    func cancelledProviderDoesNotPublish() async throws {
        let response = Gate()
        let fetched = Recorder()
        let published = Recorder()
        let task = Task {
            await SumiSourceSearchPipeline.run(sourceKeys: ["source"], fetch: { key in
                await fetched.append(key)
                await response.wait()
                return key
            }, prepare: { await published.append($0) })
        }
        defer { task.cancel(); Task { await response.release() } }
        try await wait { await fetched.values.count == 1 }
        task.cancel()
        await response.release()
        await task.value
        #expect(await published.values.isEmpty)
    }

    private func wait(_ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await predicate()), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(await predicate())
    }

    private actor Recorder {
        private(set) var values: [String] = []
        func append(_ value: String) { values.append(value) }
    }

    private actor Gate {
        private var released = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async {
            if released { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func release() { released = true; continuation?.resume(); continuation = nil }
    }
}
