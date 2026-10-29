@testable import Sumi
import AidokuRunner
import Foundation
import Testing

@Suite(.serialized)
struct HonbakoMangaDexPageDeliveryTests {
    private let mangaID = "11111111-1111-4111-8111-111111111111"
    private let chapterID = "22222222-2222-4222-8222-222222222222"

    @Test("Canonical chapter and page identity accompany temporary CDN URLs")
    func canonicalIdentityAndHeaders() async throws {
        let transport = try SequenceTransport([fixture(host: "old.mangadex.network")])
        let runner = HonbakoMangaDexRunner(requestInterval: .zero, transport: { try await transport.send($0) })
        #expect(runner.features.providesImageRequests)
        let pages = try await runner.getPageList(manga: manga(), chapter: .init(key: chapterID))
        let (url, context) = try page(pages, index: 2)
        #expect(context[HonbakoMangaDexPageDelivery.chapterKey] == chapterID)
        #expect(context[HonbakoMangaDexPageDelivery.pageKey] == "2")
        let request = try await runner.getImageRequest(url: url.absoluteString, context: context)
        #expect(request.url == url)
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Honbako/") == true)
        #expect(request.value(forHTTPHeaderField: "Referer") == "https://mangadex.org/")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(!request.httpShouldHandleCookies)
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests[0].cachePolicy == .reloadIgnoringLocalCacheData)
        let parameters = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems
        #expect(parameters?.first(where: { $0.name == "forcePort443" })?.value == "true")
    }

    @Test("A delayed page resolves an expired assignment rather than retrying its old host")
    func expiredAssignmentRenewsForSamePage() async throws {
        let clock = TestClock()
        let transport = try SequenceTransport([fixture(host: "old.mangadex.network"), fixture(host: "fresh.mangadex.network", prefix: "fresh")])
        let runner = HonbakoMangaDexRunner(requestInterval: .zero, now: { clock.now }, transport: { try await transport.send($0) })
        let pages = try await runner.getPageList(manga: manga(), chapter: .init(key: chapterID))
        let (url, context) = try page(pages, index: 2)
        clock.advance(601)
        let request = try await runner.getImageRequest(url: url.absoluteString, context: context)
        #expect(request.url?.host == "fresh.mangadex.network")
        #expect(request.url?.lastPathComponent == "fresh03.jpg")
        #expect(await transport.requests.count == 2)
    }

    @Test("Simultaneous failed leaves share one fresh assignment and preserve their canonical page")
    func concurrentRecoveryCoalesces() async throws {
        let transport = try SequenceTransport([fixture(host: "old.mangadex.network"), fixture(host: "fresh.mangadex.network")], delay: .milliseconds(30))
        let runner = HonbakoMangaDexRunner(requestInterval: .zero, transport: { try await transport.send($0) })
        let pages = try await runner.getPageList(manga: manga(), chapter: .init(key: chapterID))
        let (url, context) = try page(pages, index: 2)
        let recovered = try await withThrowingTaskGroup(of: URLRequest?.self) { group in
            for _ in 0..<8 { group.addTask { try await runner.recoveryImageRequest(url: url, context: context) } }
            var values: [URLRequest] = []
            for try await value in group { if let value { values.append(value) } }
            return values
        }
        #expect(recovered.count == 8)
        #expect(recovered.allSatisfy { $0.url?.host == "fresh.mangadex.network" && $0.url?.lastPathComponent == "03.jpg" })
        #expect(recovered.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
        #expect(await transport.requests.count == 2)
        _ = try await runner.recoveryImageRequest(url: url, context: context)
        #expect(await transport.requests.count == 2, "A just-completed batch must not trigger another assignment for every leaf")
    }

    @Test("A later explicit retry can renew again instead of pinning a failed replacement forever")
    func laterRecoveryCanRenewAgain() async throws {
        let clock = TestClock()
        let transport = try SequenceTransport([fixture(host: "old.mangadex.network"), fixture(host: "second.mangadex.network"), fixture(host: "third.mangadex.network")])
        let runner = HonbakoMangaDexRunner(requestInterval: .zero, now: { clock.now }, transport: { try await transport.send($0) })
        let pages = try await runner.getPageList(manga: manga(), chapter: .init(key: chapterID))
        let (url, context) = try page(pages, index: 0)
        _ = try await runner.recoveryImageRequest(url: url, context: context)
        clock.advance(6)
        let request = try #require(try await runner.recoveryImageRequest(url: url, context: context))
        #expect(request.url?.host == "third.mangadex.network")
        #expect(await transport.requests.count == 3)
    }

    @Test("A failed assignment request is retryable and cannot replace the previous valid manifest")
    func failedRenewalDoesNotPoisonCache() async throws {
        let transport = try SequenceTransport([fixture(host: "old.mangadex.network"), fixture(host: "unused.mangadex.network"), fixture(host: "fresh.mangadex.network")], statuses: [200, 503, 200])
        let runner = HonbakoMangaDexRunner(requestInterval: .zero, transport: { try await transport.send($0) })
        let pages = try await runner.getPageList(manga: manga(), chapter: .init(key: chapterID))
        let (url, context) = try page(pages, index: 1)
        await #expect(throws: HonbakoMangaDexError.self) { try await runner.recoveryImageRequest(url: url, context: context) }
        let request = try #require(try await runner.recoveryImageRequest(url: url, context: context))
        #expect(request.url?.host == "fresh.mangadex.network")
        #expect(await transport.requests.count == 3)
    }

    @Test("Missing, malformed and unrelated context cannot request an unrelated chapter assignment")
    func ignoresNonChapterImagesAndInvalidContext() async throws {
        let transport = try SequenceTransport([fixture(host: "unused.mangadex.network")])
        let runner = HonbakoMangaDexRunner(requestInterval: .zero, transport: { try await transport.send($0) })
        let cover = URL(string: "https://uploads.mangadex.org/covers/title/cover.jpg")!
        #expect(try await runner.recoveryImageRequest(url: cover, context: nil) == nil)
        let valid: PageContext = [HonbakoMangaDexPageDelivery.chapterKey: chapterID,
            HonbakoMangaDexPageDelivery.pageKey: "0", HonbakoMangaDexPageDelivery.fileKey: "01.jpg"]
        #expect(try await runner.recoveryImageRequest(url: cover, context: valid) == nil)
        let url = URL(string: "https://old.mangadex.network/data/hash/01.jpg")!
        for badIndex in ["-1", "512", "not-a-page"] {
            var context = valid
            context[HonbakoMangaDexPageDelivery.pageKey] = badIndex
            #expect(try await runner.recoveryImageRequest(url: url, context: context) == nil)
        }
        var context = valid
        context[HonbakoMangaDexPageDelivery.chapterKey] = "not-a-chapter"
        #expect(try await runner.recoveryImageRequest(url: url, context: context) == nil)
        #expect(await transport.requests.isEmpty)
    }

    private func manga() -> AidokuRunner.Manga { .init(sourceKey: HonbakoMangaDexRunner.sourceKey, key: mangaID, title: "Fixture") }

    private func fixture(host: String, prefix: String = "") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["result": "ok", "baseUrl": "https://\(host)",
            "chapter": ["hash": "chapterhash", "data": ["\(prefix)01.jpg", "\(prefix)02.jpg", "\(prefix)03.jpg"]]])
    }

    private func page(_ pages: [AidokuRunner.Page], index: Int) throws -> (URL, PageContext) {
        guard case .url(let url, let context) = pages[index].content else { throw HonbakoMangaDexError.invalidResponse }
        return (url, try #require(context))
    }

    private actor SequenceTransport {
        let values: [Data]
        let statuses: [Int]
        let delay: Duration
        private(set) var requests: [URLRequest] = []
        init(_ values: [Data], statuses: [Int] = [], delay: Duration = .zero) {
            self.values = values
            self.statuses = statuses
            self.delay = delay
        }
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let index = min(requests.count, values.count - 1)
            requests.append(request)
            if delay > .zero { try await Task.sleep(for: delay) }
            let status = statuses.indices.contains(index) ? statuses[index] : 200
            return (values[index], HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_000)
        var now: Date { lock.withLock { value } }
        func advance(_ interval: TimeInterval) { lock.withLock { value.addTimeInterval(interval) } }
    }
}
