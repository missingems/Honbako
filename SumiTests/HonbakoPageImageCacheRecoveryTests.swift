@testable import Sumi
import Foundation
import Nuke
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct HonbakoPageImageCacheRecoveryTests {
    @Test("Retry bypasses corrupt HTTP200 bytes in Nuke even when the page URL is unchanged")
    func sameURLCorruptDataRecovery() async throws {
        let bad = Data("temporary CDN response, not an image".utf8)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let good = try #require(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 12), format: format).image { output in
            UIColor.white.setFill()
            output.fill(CGRect(x: 0, y: 0, width: 8, height: 12))
        }.pngData())
        let cache = PageRecoveryMemoryDataCache()
        let loader = PageRecoveryDataLoader(payloads: [bad, good])
        var configuration = ImagePipeline.Configuration()
        configuration.dataLoader = loader
        configuration.dataCache = cache
        configuration.imageCache = ImageCache()
        configuration.dataCachePolicy = .storeOriginalData
        configuration.isResumableDataEnabled = false
        let pipeline = ImagePipeline(configuration: configuration)
        defer { pipeline.invalidate(); cache.removeAll() }
        let url = try #require(URL(string: "https://owned-page-cache-fixture.invalid/same-page.png"))
        let ordinary = ImageRequest(url: url)
        let first = try? await pipeline.image(for: ordinary)
        #expect(first == nil)
        #expect(loader.requestCount == 1)
        #expect(pipeline.cache.cachedData(for: ordinary) == bad,
                "HTTP200 original bytes can survive a later decoding failure")

        // Nuke already retries undecodable cached bytes automatically. This
        // checks our requested retry directly without assuming otherwise.
        let retry = SumiPageImageRetryRequest.make(from: ordinary)
        let recovered = try await pipeline.image(for: retry)
        #expect(recovered.size == CGSize(width: 8, height: 12))
        #expect(loader.requestCount == 2)
        #expect(pipeline.cache.cachedData(for: ordinary) == good)
        _ = try await pipeline.image(for: ordinary)
        #expect(loader.requestCount == 2, "A successful repair restores ordinary cache reuse")
    }

    @Test("Explicit retry replaces a stale valid image while ordinary page loads reuse it")
    func sameURLStaleValidImageReload() async throws {
        let old = try png(size: CGSize(width: 6, height: 9))
        let updated = try png(size: CGSize(width: 8, height: 12))
        let cache = PageRecoveryMemoryDataCache()
        let loader = PageRecoveryDataLoader(payloads: [old, updated])
        var configuration = ImagePipeline.Configuration()
        configuration.dataLoader = loader
        configuration.dataCache = cache
        configuration.imageCache = ImageCache()
        configuration.dataCachePolicy = .storeOriginalData
        let pipeline = ImagePipeline(configuration: configuration)
        defer { pipeline.invalidate(); cache.removeAll() }
        let url = try #require(URL(string: "https://owned-page-cache-fixture.invalid/updated-page.png"))
        let ordinary = ImageRequest(url: url)
        _ = try await pipeline.image(for: ordinary)
        let reused = try await pipeline.image(for: ordinary)
        #expect(reused.size == CGSize(width: 6, height: 9))
        #expect(loader.requestCount == 1, "Ordinary page loads preserve normal memory/disk caching")
        let refreshed = try await pipeline.image(for: SumiPageImageRetryRequest.make(from: ordinary))
        #expect(refreshed.size == CGSize(width: 8, height: 12))
        #expect(loader.requestCount == 2, "An explicit retry must fetch the corrected response at the same URL")
        #expect(pipeline.cache.cachedData(for: ordinary) == updated)
    }

    @Test("Forced retry preserves source headers and processing while ordinary requests keep caching")
    func retryPreservesIdentityAndOrdinaryCachePolicy() throws {
        let url = try #require(URL(string: "https://owned-page-cache-fixture.invalid/page.png"))
        var transport = URLRequest(url: url)
        transport.setValue("Honbako fixture", forHTTPHeaderField: "User-Agent")
        transport.setValue("https://mangadex.org/", forHTTPHeaderField: "Referer")
        var ordinary = ImageRequest(urlRequest: transport, processors: [DownsampleProcessor(width: 100, scaleFactor: 2)],
            priority: .high, options: [.skipDecompression], userInfo: [.processesKey: false])
        ordinary.imageID = "canonical-fixture-page"
        ordinary.scale = 2
        let retry = SumiPageImageRetryRequest.make(from: ordinary)
        #expect(retry.url == ordinary.url)
        #expect(retry.urlRequest?.allHTTPHeaderFields == ordinary.urlRequest?.allHTTPHeaderFields)
        #expect(retry.urlRequest?.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(retry.options.contains(.reloadIgnoringCachedData))
        #expect(retry.options.contains(.skipDecompression))
        #expect(retry.processors.map(\.identifier) == ordinary.processors.map(\.identifier))
        #expect(retry.imageID == ordinary.imageID)
        #expect(retry.scale == ordinary.scale)
        #expect(retry.priority == ordinary.priority)
        #expect(retry.userInfo[.processesKey] as? Bool == false)
        #expect(!ordinary.options.contains(.reloadIgnoringCachedData))
        #expect(ordinary.urlRequest?.cachePolicy == .useProtocolCachePolicy)
    }

    private func png(size: CGSize) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return try #require(UIGraphicsImageRenderer(size: size, format: format).image { output in
            UIColor.white.setFill()
            output.fill(CGRect(origin: .zero, size: size))
        }.pngData())
    }
}

private final class PageRecoveryMemoryDataCache: DataCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func cachedData(for key: String) -> Data? { lock.withLock { values[key] } }
    func containsData(for key: String) -> Bool { lock.withLock { values[key] != nil } }
    func storeData(_ data: Data, for key: String) { lock.withLock { values[key] = data } }
    func removeData(for key: String) { _ = lock.withLock { values.removeValue(forKey: key) } }
    func removeAll() { lock.withLock { values.removeAll() } }
}

private final class PageRecoveryDataLoader: DataLoading, @unchecked Sendable {
    private let lock = NSLock()
    private let payloads: [Data]
    private var count = 0
    var requestCount: Int { lock.withLock { count } }
    init(payloads: [Data]) { self.payloads = payloads }
    func loadData(with request: URLRequest,
                  didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
                  completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let payload = lock.withLock {
            let payload = payloads[min(count, payloads.count - 1)]
            count += 1
            return payload
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "image/png", "Content-Length": String(payload.count)])!
        didReceiveData(payload, response)
        completion(nil)
        return PageRecoveryNoopCancellation()
    }
}

private struct PageRecoveryNoopCancellation: Cancellable {
    func cancel() {}
}
