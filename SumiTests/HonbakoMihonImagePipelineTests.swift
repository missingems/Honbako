@testable import Sumi
import AidokuRunner
import CryptoKit
import Foundation
import Nuke
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct HonbakoMihonImagePipelineTests {
    private let sourceID = "7628940012345678901"
    private var sourceKey: String { "mihon.\(sourceID)" }
    private let firstContext = ["slot": "one", "runtime": "already-processed"]

    @Test("Reader pages and differently sized cached previews consume the same runtime bytes without URLSession or a second extension processor")
    func pagedReaderAndPreviewCache() async throws {
        let first = try imageData(color: .green, jpeg: false)
        let runner = Provider(payloads: ["one": first])
        let source = makeSource(runner)
        let network = NetworkTrap()
        let pipeline = makePipeline(network)
        defer { pipeline.invalidate() }
        let url = opaqueURL(1)
        let pageRequest = await ReaderPageView.imageRequest(url: url, context: firstContext, source: source,
            downsampleWidth: 24, displayScale: 1)
        #expect(pageRequest.urlRequest == nil)
        #expect(pageRequest.userInfo[.processesKey] as? Bool == false)
        #expect(!pageRequest.processors.contains { $0 is PageInterceptorProcessor })
        let page = try await pipeline.image(for: pageRequest)
        #expect(page.size.width > 0 && page.size.height > 0)
        let processor = ImageProcessors.Resize(size: CGSize(width: 10, height: 15), unit: .pixels)
        let previewRequest = try #require(MihonRuntimeImageLoader.imageRequest(url: url, context: firstContext,
            source: source, processors: [processor]))
        let preview = try await pipeline.image(for: previewRequest)
        #expect(preview.size.width == 10 && preview.size.height == 15)
        let cachedPreview = try await pipeline.image(for: previewRequest)
        #expect(cachedPreview.size == preview.size)
        var originalRequest = previewRequest
        originalRequest.processors = []
        let original = try await pipeline.data(for: originalRequest).0
        #expect(original == first)
        #expect(await runner.receivedContexts == [firstContext])
        #expect(await runner.requestCalls == 0)
        #expect(await runner.processorCalls == 0)
        #expect(network.count == 0)
    }

    @Test("Webtoon loading uses the lazy runtime provider instead of its legacy network/processor path")
    func webtoonReaderUsesProvider() async throws {
        let first = try imageData(color: .orange, jpeg: false)
        let runner = Provider(payloads: ["one": first])
        let source = makeSource(runner)
        let network = NetworkTrap()
        let pipeline = makePipeline(network)
        let store = ReaderTemporaryPageStore()
        defer { pipeline.invalidate(); Task { await store.removeAll() } }
        let page = Sumi.Page(sourceId: sourceKey, chapterId: "runtime-webtoon", index: 0,
            imageURL: opaqueURL(1).absoluteString, context: firstContext)
        let node = ReaderWebtoonPageNode(source: source, page: page, temporaryPageStore: store,
            pillarboxLayoutState: .init(), imagePipeline: pipeline)
        await node.loadPage()
        #expect(node.image != nil)
        #expect(await runner.receivedContexts == [firstContext])
        #expect(await runner.requestCalls == 0)
        #expect(await runner.processorCalls == 0)
        #expect(network.count == 0)
        await store.removeAll()
    }

    @Test("Missing providers, wrong source identities and raw HTTP URLs fail without any network fallback")
    func failuresStayOffNetwork() async throws {
        let runner = Provider(payloads: ["one": try imageData(color: .blue, jpeg: false)])
        let source = makeSource(runner)
        let wrongSource = AidokuRunner.Source(key: "mihon.42", name: "Wrong", version: 1, contentRating: .safe, runner: runner)
        let network = NetworkTrap()
        let pipeline = makePipeline(network)
        defer { pipeline.invalidate() }
        let cases: [(URL, AidokuRunner.PageContext?, AidokuRunner.Source?)] = [
            (opaqueURL(1), firstContext, nil),
            (opaqueURL(1), firstContext, wrongSource),
            (opaqueURL(1), nil, source),
            (URL(string: "https://provider.example.invalid/raw-page.png")!, firstContext, source)
        ]
        for (url, context, source) in cases {
            let request = try #require(MihonRuntimeImageLoader.imageRequest(url: url, context: context, source: source, processors: []))
            do { _ = try await pipeline.image(for: request); Issue.record("Invalid runtime image request succeeded") }
            catch { /* An image-load error is expected; the data loader must stay unused. */ }
        }
        #expect(network.count == 0)
        #expect(await runner.receivedContexts.isEmpty)
        #expect(await runner.requestCalls == 0)
        #expect(!MihonRuntimeImageLoader.handles(url: URL(fileURLWithPath: "/downloaded/page.png"), source: source))
    }

    @Test("Offline downloads retain each runtime image's original bytes, MIME extension, context and page order")
    func offlineDownloadsUseSameBytes() async throws {
        let first = try imageData(color: .red, jpeg: true)
        let second = try imageData(color: .blue, jpeg: true)
        let secondContext = ["slot": "two", "runtime": "already-processed"]
        let runner = Provider(payloads: ["one": first, "two": second], pages: [
            .init(content: .url(url: opaqueURL(1), context: firstContext)),
            .init(content: .url(url: opaqueURL(2), context: secondContext))
        ], mime: "image/jpeg")
        let source = makeSource(runner)
        let manga = AidokuRunner.Manga(sourceKey: sourceKey, key: "pipeline-offline-\(UUID())", title: "Original Runtime Test")
        let chapter = AidokuRunner.Chapter(key: "original-chapter")
        let download = Download.from(manga: manga, chapter: chapter)
        let cache = DownloadCache()
        let events = Events()
        let defaults = UserDefaults.standard
        let compressionKey = AppSettings.downloads.compress.key
        let previousCompression = defaults.object(forKey: compressionKey)
        defaults.set(false, forKey: compressionKey)
        let worker = DownloadTask(id: sourceKey, cache: cache, downloads: [download], sourceLookup: { key in key == source.key ? source : nil })
        defer {
            Task { await worker.cancel() }
            cache.directory(for: manga.identifier).removeItem()
            defaults.set(previousCompression, forKey: compressionKey)
        }
        await worker.setDelegate(delegate: events)
        await worker.resume()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await events.finished.isEmpty, await events.failed.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let finished = try #require(await events.finished.first)
        #expect(finished.status == .finished)
        #expect(await events.failed.isEmpty)
        let folder = cache.directory(for: download.chapterIdentifier)
        #expect(try Data(contentsOf: folder.appendingPathComponent("001.jpg")) == first)
        #expect(try Data(contentsOf: folder.appendingPathComponent("002.jpg")) == second)
        #expect(await runner.receivedContexts.count == 2)
        #expect(Set(await runner.receivedContexts.compactMap { $0?["slot"] }) == ["one", "two"])
        #expect(await runner.requestCalls == 0)
        #expect(await runner.processorCalls == 0)
        let pages = await DownloadManager.shared.getDownloadedPages(for: download.chapterIdentifier)
        #expect(pages.count == 2)
    }

    @Test("Ordinary sources keep their request modifications and extension processor")
    func legacyPathUnchanged() async throws {
        let runner = LegacyProvider()
        let source = AidokuRunner.Source(key: "ordinary-source", name: "Ordinary", version: 1, contentRating: .safe, runner: runner)
        let request = await ReaderPageView.imageRequest(url: URL(string: "https://provider.example.invalid/original.png")!,
            context: ["original": "context"], source: source)
        #expect(request.urlRequest?.url?.host == "modified.example.invalid")
        #expect(request.userInfo[.processesKey] as? Bool == true)
        #expect(request.processors.contains { $0 is PageInterceptorProcessor })
        #expect(await runner.requests == 1)
    }

    private func opaqueURL(_ index: Int) -> URL {
        URL(string: "\(MihonRunner.imageScheme)://runtime/\(sourceID)/\(String(repeating: "0", count: 63))\(index)")!
    }
    private func makeSource(_ runner: Provider) -> AidokuRunner.Source {
        .init(key: sourceKey, name: "Runtime Provider", version: 1, contentRating: .safe, runner: runner)
    }
    private func imageData(color: UIColor, jpeg: Bool) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60), format: format).image { output in
            color.setFill(); output.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
        return try #require(jpeg ? image.jpegData(compressionQuality: 1) : image.pngData())
    }
    private func makePipeline(_ network: NetworkTrap) -> ImagePipeline {
        ImagePipeline {
            $0.dataLoader = network
            $0.dataCache = MemoryDataCache()
            $0.imageCache = ImageCache()
            $0.isRateLimiterEnabled = false
            $0.isDecompressionEnabled = false
        }
    }

    private actor Provider: AidokuRunner.Runner, MihonRuntimeImageProviding {
        nonisolated let features = AidokuRunner.SourceFeatures(processesPages: true, providesImageRequests: true)
        private let payloads: [String: Data]
        private let pages: [AidokuRunner.Page]
        private let mime: String
        private(set) var receivedContexts: [AidokuRunner.PageContext?] = []
        private(set) var requestCalls = 0
        private(set) var processorCalls = 0
        init(payloads: [String: Data], pages: [AidokuRunner.Page] = [], mime: String = "image/png") {
            self.payloads = payloads; self.pages = pages; self.mime = mime
        }
        func runtimeImageData(url: URL, context: AidokuRunner.PageContext?) async throws -> MihonRuntimeImagePayload {
            receivedContexts.append(context)
            let slot = context?["slot"] ?? ""
            guard let data = payloads[slot] else { throw MihonRuntimeError.invalidPageContext }
            return .init(data: data, mediaType: mime, reportedByteCount: data.count,
                reportedSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        }
        func getImageRequest(url: String, context: AidokuRunner.PageContext?) async throws -> URLRequest {
            requestCalls += 1; throw MihonRuntimeError.imageLoaderRequired
        }
        func processPageImage(response: AidokuRunner.Response, context: AidokuRunner.PageContext?) async throws -> AidokuRunner.PlatformImage? {
            processorCalls += 1; throw MihonRuntimeError.invalidInput
        }
        func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult { .init(entries: [], hasNextPage: false) }
        func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga { manga }
        func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] { pages }
    }
    private actor LegacyProvider: AidokuRunner.Runner {
        nonisolated let features = AidokuRunner.SourceFeatures(processesPages: true, providesImageRequests: true)
        private(set) var requests = 0
        func getImageRequest(url: String, context: AidokuRunner.PageContext?) async throws -> URLRequest {
            requests += 1; return URLRequest(url: URL(string: "https://modified.example.invalid/image.png")!)
        }
        func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult { .init(entries: [], hasNextPage: false) }
        func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga { manga }
        func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] { [] }
    }
    private actor Events: DownloadTaskDelegate {
        private(set) var finished: [Download] = []
        private(set) var failed: [Download] = []
        func taskCancelled(task: DownloadTask) async {}
        func taskPaused(task: DownloadTask) async {}
        func taskFinished(task: DownloadTask) async {}
        func downloadProgressChanged(download: Download) async {}
        func downloadFinished(download: Download) async { finished.append(download) }
        func downloadFailed(download: Download) async { failed.append(download) }
        func downloadCancelled(download: Download) async {}
    }
    private final class NetworkTrap: DataLoading, @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        var count: Int { lock.withLock { calls } }
        func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
                      completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
            lock.withLock { calls += 1 }
            completion(URLError(.unsupportedURL))
            return NoopCancellation()
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
