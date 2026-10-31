@testable import Sumi
import Foundation
import Nuke
import Testing
import UIKit

@MainActor
struct SumiPageImageFetchTests {
    @Test("NukeUI reuses a warm page and explicit retry still bypasses it")
    func cachedPageAndExplicitRetry() async throws {
        let old = image(size: CGSize(width: 6, height: 9))
        let updated = try #require(image(size: CGSize(width: 8, height: 12)).pngData())
        let state = FetchDataState(bytes: updated)
        let pipeline = makePipeline()
        defer { pipeline.invalidate() }
        let request = ImageRequest(id: "warm-page-\(UUID())", data: { await state.data() })
        pipeline.cache.storeCachedImage(ImageContainer(image: old), for: request)
        let fetch = SumiPageImageFetch(pipeline: pipeline)
        let warm = try await fetch.response(for: request)
        #expect(warm.image === old)
        #expect(warm.cacheType == .memory)
        #expect(await state.calls == 0)
        let refreshed = try await fetch.response(for: SumiPageImageRetryRequest.make(from: request))
        #expect(refreshed.image.size == CGSize(width: 8, height: 12))
        #expect(await state.calls == 1)
        #expect(!fetch.isLoading)
    }

    @Test("Cancellation resumes an awaiting reader even when the data provider has not returned")
    func cancellationResumesReader() async throws {
        let bytes = try #require(image(size: CGSize(width: 8, height: 12)).pngData())
        let state = FetchDataState(bytes: bytes, held: true)
        let pipeline = makePipeline()
        defer { pipeline.invalidate() }
        let fetch = SumiPageImageFetch(pipeline: pipeline)
        defer { fetch.cancel() }
        let request = ImageRequest(id: "cancelled-page-\(UUID())", data: { await state.data() })
        let loading = Task { () -> Bool in
            do { _ = try await fetch.response(for: request); return false }
            catch { return SumiPageImageLoadCancellation.contains(error) }
        }
        try await wait { await state.calls == 1 }
        loading.cancel()
        try await wait { !fetch.isLoading }
        // Resolve a noncooperative provider after the reader has already left.
        await state.release()
        #expect(await loading.value)
    }

    @Test("A newer page replaces an awaiting load and ignores its late provider result")
    func supersededPageCannotReplaceNewPage() async throws {
        let oldBytes = try #require(image(size: CGSize(width: 6, height: 9)).pngData())
        let newBytes = try #require(image(size: CGSize(width: 8, height: 12)).pngData())
        let state = FetchDataState(bytes: oldBytes, held: true)
        let nextState = FetchDataState(bytes: newBytes, held: true)
        let pipeline = makePipeline()
        defer { pipeline.invalidate() }
        let fetch = SumiPageImageFetch(pipeline: pipeline)
        defer { fetch.cancel() }
        let request = ImageRequest(id: "old-page-\(UUID())", data: { await state.data() })
        let started = StartedImageTask()
        let old = Task { () -> Bool in
            do { _ = try await fetch.response(for: request, onStart: { started.task = $0 }); return false }
            catch { return SumiPageImageLoadCancellation.contains(error) }
        }
        try await wait { await state.calls == 1 }
        let next = ImageRequest(id: "new-page-\(UUID())", data: { await nextState.data() })
        let loadingNext = Task { try await fetch.response(for: next) }
        try await wait { await nextState.calls == 1 }
        fetch.cancel(task: try #require(started.task))
        #expect(fetch.isLoading, "A delayed cancellation for the old request must not stop its replacement")
        await nextState.release()
        let result = try await loadingNext.value
        await state.release()
        #expect(await old.value)
        #expect(result.image.size == CGSize(width: 8, height: 12))
        #expect(!fetch.isLoading)
    }

    private func makePipeline() -> ImagePipeline {
        var configuration = ImagePipeline.Configuration()
        configuration.imageCache = ImageCache()
        configuration.dataCache = nil
        return ImagePipeline(configuration: configuration)
    }

    private func image(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { output in
            UIColor.white.setFill(); output.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await condition()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(await condition())
    }
}

private actor FetchDataState {
    private let bytes: Data
    private var held: Bool
    private var waiting: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    init(bytes: Data, held: Bool = false) { self.bytes = bytes; self.held = held }
    func data() async -> Data {
        calls += 1
        if held { await withCheckedContinuation { waiting = $0 } }
        return bytes
    }
    func release() { held = false; waiting?.resume(); waiting = nil }
}

@MainActor
private final class StartedImageTask { var task: ImageTask? }
