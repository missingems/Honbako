@testable import Sumi
import AidokuRunner
import CryptoKit
import Foundation
import Nuke
import Testing
import UIKit

@MainActor
struct HonbakoMihonCoverPipelineTests {
    private let sourceID = "4508733312114627536"
    private var sourceKey: String { "mihon.\(sourceID)" }
    private let coverURL = URL(string: "https://books.example.invalid/covers/original.png")!

    @Test("Generic cover views and real library/search warming share extension cover bytes without URLSession or a second cover hook")
    func genericAndArtworkLoader() async throws {
        let bytes = try png()
        let provider = Provider(sourceKey: sourceKey, scope: String(repeating: "a", count: 64), data: bytes)
        let source = makeSource(provider)
        let network = NetworkTrap()
        let pipeline = makePipeline(network)
        defer { pipeline.invalidate() }
        let generic = await SourceImageView.makeImageRequest(url: coverURL.absoluteString, source: source)
        #expect(generic.urlRequest == nil)
        #expect(generic.userInfo[.processesKey] as? Bool == false)
        #expect(try await pipeline.data(for: generic).0 == bytes)
        let book = SumiBook(manga: .init(sourceKey: sourceKey, key: "/series/original", title: "Original", cover: coverURL.absoluteString))
        let loader = SumiCoverArtworkLoader(imagePipeline: pipeline)
        let artwork = try #require(await loader.loadCover(for: book, source: source))
        #expect(artwork.size.width > 0 && artwork.size.height > 0)
        #expect(loader.cachedCover(for: book) === artwork)
        #expect(await loader.loadCover(for: book, source: source) === artwork)
        let thumbnail = try #require(MihonRuntimeCoverImageLoader.imageRequest(url: coverURL, source: source,
            processors: [ImageProcessors.Resize(size: CGSize(width: 12, height: 18), unit: .pixels)]))
        let image = try await pipeline.image(for: thumbnail)
        #expect(image.size == CGSize(width: 12, height: 18))
        #expect(await provider.covers == [coverURL])
        #expect(await provider.pageRequestCalls == 0)
        #expect(await provider.coverProcessorCalls == 0)
        #expect(network.count == 0)
    }

    @Test("A real Runner discovers its exact source before sending the dedicated native cover command with the reviewed identity")
    func realRunnerCoverWire() async throws {
        let bytes = try png()
        let payload = MihonRuntimeImagePayload(data: bytes, mediaType: "image/png", reportedByteCount: bytes.count)
        let calls = Calls()
        let identity = try MihonJSONRuntimeTransport.PackageIdentity(extensionPath: "/reviewed/komga.jar", packageSHA256: String(repeating: "a", count: 64),
            packageName: "eu.kanade.tachiyomi.extension.all.komga", versionName: "1.6.74")
        let transport = MihonJSONRuntimeTransport(packageIdentity: identity, executeJSON: { input in
            await calls.metadata(input)
            return "{\"ok\":true,\"result\":{\"package\":\"eu.kanade.tachiyomi.extension.all.komga\",\"version\":\"1.6.74\",\"sources\":[{\"id\":\"4508733312114627536\",\"name\":\"Komga\",\"language\":\"en\"}]}}"
        }, imageBytes: { input in await calls.image(input); return payload })
        let runner = try makeRunner(transport: transport)
        let source = makeSource(runner)
        let network = NetworkTrap()
        let pipeline = makePipeline(network)
        defer { pipeline.invalidate() }
        let request = try #require(MihonRuntimeCoverImageLoader.imageRequest(url: coverURL, source: source))
        #expect(try await pipeline.data(for: request).0 == bytes)
        let metadata = await calls.metadataInputs
        let images = await calls.imageInputs
        #expect(metadata.count == 1 && images.count == 1)
        let discovery = try object(try #require(metadata.first))
        let cover = try object(try #require(images.first))
        #expect(discovery["operation"] as? String == "discover")
        #expect(cover["operation"] as? String == "cover")
        #expect(cover["url"] as? String == coverURL.absoluteString)
        #expect(cover["page"] == nil)
        #expect(cover["sourceId"] as? String == sourceID)
        #expect(cover["packageSHA256"] as? String == identity.packageSHA256)
        #expect(cover["preferences"] as? [String: String] == ["Address": "https://books.example.invalid"])
        #expect(network.count == 0)
    }

    @Test("Runtime cover cache identity changes with package revision, preferences, language, local artifact and exact source")
    func packageScopedCacheIdentity() throws {
        let transport = UnavailableTransport()
        let original = try makeRunner(transport: transport)
        let equivalent = try makeRunner(transport: transport)
        #expect(original.runtimeCoverCacheScope == equivalent.runtimeCoverCacheScope)
        let variants = [
            try makeRunner(transport: transport, hash: String(repeating: "b", count: 64)),
            try makeRunner(transport: transport, version: "1.6.75"),
            try makeRunner(transport: transport, path: "/reviewed/other.jar"),
            try makeRunner(transport: transport, language: "ja"),
            try makeRunner(transport: transport, id: "4508733312114627537"),
            try makeRunner(transport: transport, preferences: ["Address": "https://other.example.invalid"])
        ]
        let originalRequest = try #require(MihonRuntimeCoverImageLoader.imageRequest(url: coverURL, source: makeSource(original)))
        var identifiers: Set<String> = []
        for runner in variants {
            #expect(runner.runtimeCoverCacheScope != original.runtimeCoverCacheScope)
            let source = AidokuRunner.Source(key: runner.configuration.sourceKey, name: "Runtime", version: 1, contentRating: .safe, runner: runner)
            let request = try #require(MihonRuntimeCoverImageLoader.imageRequest(url: coverURL, source: source))
            #expect(request.imageID != originalRequest.imageID)
            identifiers.insert(try #require(request.imageID))
        }
        #expect(identifiers.count == variants.count)
    }

    @Test("Unavailable providers, wrong runtime identity and unsafe cover URLs fail without a raw network fallback")
    func unavailableCoversFailClosed() async throws {
        let provider = Provider(sourceKey: sourceKey, scope: "scope", data: try png())
        let source = makeSource(provider)
        let wrongSource = AidokuRunner.Source(key: "mihon.42", name: "Wrong", version: 1, contentRating: .safe, runner: provider)
        let missingProvider = AidokuRunner.Source(key: sourceKey, name: "Missing", version: 1, contentRating: .safe, runner: LegacyProvider())
        let network = NetworkTrap()
        let pipeline = makePipeline(network)
        defer { pipeline.invalidate() }
        let cases: [(URL, AidokuRunner.Source?, String?)] = [
            (coverURL, nil, sourceKey),
            (coverURL, missingProvider, nil),
            (coverURL, wrongSource, nil),
            (coverURL, source, "mihon.42"),
            (URL(string: "https://user:secret@books.example.invalid/cover.png")!, source, nil),
            (URL(string: "honbako-mihon-page://runtime/4508733312114627536/context")!, source, nil)
        ]
        for (url, source, expectedKey) in cases {
            let request = try #require(MihonRuntimeCoverImageLoader.imageRequest(url: url, source: source, sourceKey: expectedKey))
            #expect(request.urlRequest == nil)
            do { _ = try await pipeline.image(for: request); Issue.record("Invalid cover request succeeded") }
            catch { /* The runtime input must fail without invoking the HTTP data loader. */ }
        }
        #expect(await provider.covers.isEmpty)
        #expect(await provider.pageRequestCalls == 0)
        #expect(network.count == 0)
    }

    @Test("Ordinary cover request modifications and downloaded cover files retain their existing paths")
    func legacyAndLocalCovers() async throws {
        let legacy = LegacyProvider()
        let source = AidokuRunner.Source(key: "ordinary-source", name: "Legacy", version: 1, contentRating: .safe, runner: legacy)
        #expect(MihonRuntimeCoverImageLoader.imageRequest(url: coverURL, source: source) == nil)
        let request = await SourceImageView.makeImageRequest(url: coverURL.absoluteString, source: source)
        #expect(request.urlRequest?.url?.host == "modified.example.invalid")
        #expect(request.userInfo[.processesKey] as? Bool == true)
        #expect(await legacy.calls == 1)
        let runtime = Provider(sourceKey: sourceKey, scope: "scope", data: try png())
        let runtimeSource = makeSource(runtime)
        let local = URL(fileURLWithPath: "/downloaded/cover.png")
        #expect(!MihonRuntimeCoverImageLoader.handles(url: local, source: runtimeSource))
        let localRequest = await SourceImageView.makeImageRequest(url: local.absoluteString, source: runtimeSource)
        #expect(localRequest.url == local)
        #expect(await runtime.pageRequestCalls == 0)
    }

    @Test("Cancelling a cover load prevents publication after an extension ignores cancellation")
    func cancellation() async throws {
        let gate = Gate()
        let provider = Provider(sourceKey: sourceKey, scope: "scope", data: try png(), gate: gate)
        let source = makeSource(provider)
        let task = Task { try await MihonRuntimeCoverImageLoader.imageData(url: coverURL, source: source) }
        await gate.waitUntilStarted()
        task.cancel()
        await gate.release()
        do { _ = try await task.value; Issue.record("Cancelled cover was published") }
        catch { #expect(error is CancellationError) }
    }

    private func makeSource(_ runner: any AidokuRunner.Runner) -> AidokuRunner.Source {
        .init(key: sourceKey, name: "Runtime", version: 1, contentRating: .safe, runner: runner)
    }
    private func makeRunner(transport: any MihonRuntimeTransport, hash: String = String(repeating: "a", count: 64),
                            version: String = "1.6.74", path: String = "/reviewed/komga.jar", language: String = "en",
                            id: String = "4508733312114627536", preferences: [String: String] = ["Address": "https://books.example.invalid"]) throws -> MihonRunner {
        let configuration = try MihonRunner.Configuration(extensionURL: URL(fileURLWithPath: path),
            packageName: "eu.kanade.tachiyomi.extension.all.komga", versionName: version,
            packageSHA256: hash, sourceID: id, language: language, preferences: preferences)
        return MihonRunner(configuration: configuration, transport: transport)
    }
    private func png() throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60), format: format).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
        return try #require(image.pngData())
    }
    private func object(_ input: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
    }
    private func makePipeline(_ network: NetworkTrap) -> ImagePipeline {
        ImagePipeline {
            $0.dataLoader = network
            $0.dataCache = MemoryDataCache()
            $0.dataCachePolicy = .storeOriginalData
            $0.imageCache = ImageCache()
            $0.isRateLimiterEnabled = false
            $0.isDecompressionEnabled = false
        }
    }
    private actor Provider: AidokuRunner.Runner, MihonRuntimeCoverImageProviding {
        nonisolated let features = AidokuRunner.SourceFeatures(processesCovers: true, providesImageRequests: true)
        nonisolated let runtimeCoverSourceKey: String
        nonisolated let runtimeCoverCacheScope: String
        let data: Data
        let gate: Gate?
        private(set) var covers: [URL] = []
        private(set) var pageRequestCalls = 0
        private(set) var coverProcessorCalls = 0
        init(sourceKey: String, scope: String, data: Data, gate: Gate? = nil) {
            self.runtimeCoverSourceKey = sourceKey; self.runtimeCoverCacheScope = scope; self.data = data; self.gate = gate
        }
        func runtimeCoverData(url: URL) async throws -> MihonRuntimeImagePayload {
            covers.append(url)
            if let gate { await gate.pause() }
            return .init(data: data, mediaType: "image/png", reportedByteCount: data.count)
        }
        func getImageRequest(url: String, context: AidokuRunner.PageContext?) async throws -> URLRequest {
            pageRequestCalls += 1; throw MihonRuntimeError.imageLoaderRequired
        }
        func processCoverImage(response: AidokuRunner.Response) async throws -> AidokuRunner.PlatformImage? {
            coverProcessorCalls += 1; throw MihonRuntimeError.invalidInput
        }
        func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult { .init(entries: [], hasNextPage: false) }
        func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga { manga }
        func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] { [] }
    }
    private actor LegacyProvider: AidokuRunner.Runner {
        nonisolated let features = AidokuRunner.SourceFeatures(processesCovers: true, providesImageRequests: true)
        private(set) var calls = 0
        func getImageRequest(url: String, context: AidokuRunner.PageContext?) async throws -> URLRequest {
            calls += 1; return URLRequest(url: URL(string: "https://modified.example.invalid/cover.png")!)
        }
        func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult { .init(entries: [], hasNextPage: false) }
        func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga { manga }
        func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] { [] }
    }
    private struct UnavailableTransport: MihonRuntimeTransport {
        func execute(_ request: MihonRuntimeRequest) async throws -> Data { throw MihonRuntimeError.invalidInput }
        func imageData(_ request: MihonRuntimeImageRequest) async throws -> MihonRuntimeImagePayload { throw MihonRuntimeError.invalidInput }
    }
    private actor Calls {
        private(set) var metadataInputs: [String] = []
        private(set) var imageInputs: [String] = []
        func metadata(_ value: String) { metadataInputs.append(value) }
        func image(_ value: String) { imageInputs.append(value) }
    }
    private actor Gate {
        private var started = false
        private var startedWaiters: [CheckedContinuation<Void, Never>] = []
        private var waiting: CheckedContinuation<Void, Never>?
        func pause() async {
            await withCheckedContinuation { continuation in
                started = true; waiting = continuation
                startedWaiters.forEach { $0.resume() }; startedWaiters.removeAll()
            }
        }
        func waitUntilStarted() async {
            if started { return }
            await withCheckedContinuation { startedWaiters.append($0) }
        }
        func release() { waiting?.resume(); waiting = nil }
    }
    private final class NetworkTrap: DataLoading, @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        var count: Int { lock.withLock { calls } }
        func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
                      completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
            lock.withLock { calls += 1 }; completion(URLError(.unsupportedURL)); return NoopCancellation()
        }
    }
    private struct NoopCancellation: Cancellable { func cancel() {} }
    private final class MemoryDataCache: DataCaching, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Data] = [:]
        func cachedData(for key: String) -> Data? { lock.withLock { values[key] } }
        func containsData(for key: String) -> Bool { lock.withLock { values[key] != nil } }
        func storeData(_ data: Data, for key: String) { lock.withLock { values[key] = data } }
        func removeData(for key: String) { _ = lock.withLock { values.removeValue(forKey: key) } }
        func removeAll() { lock.withLock { values.removeAll() } }
    }
}
