@testable import Sumi
import AidokuRunner
import CryptoKit
import Foundation
import Testing

struct HonbakoMihonRunnerTests {
    private let sourceID = "4508733312114627536"
    private let sourceKey = "mihon.4508733312114627536"
    private let mangaKey = "/api/v1/series/honbako-original"
    private let chapterKey = "/api/v1/books/original-1"

    @Test("Real bridge-shaped metadata maps identities, language, status and ordered chapters without reader guesses")
    func metadataMapping() async throws {
        let transport = Transport(language: "pt-BR", responses: [
            .search: [success("{\"hasNextPage\":true,\"entries\":[\(mangaRecord)]}")],
            .details: [success("{\"manga\":\(mangaRecord),\"chapters\":[]}")],
            .chapters: [success("""
              {"manga":{"url":"\(mangaKey)","title":"Your First Chapter","status":0},"chapters":[
                {"url":"/chapter/9","name":"Ninth","number":9,"uploadedAt":1793030400000,"scanlator":"Honbako"},
                {"url":"/chapter/8","name":"Eighth","number":8.5,"uploadedAt":0,"scanlator":""}]}
              """)]
        ])
        let runner = try makeRunner(transport, language: "pt-BR")
        let result = try await runner.getSearchMangaList(query: "Your First", page: 2, filters: [])
        let manga = try #require(result.entries.first)
        #expect(result.hasNextPage)
        #expect(manga.sourceKey == sourceKey && manga.key == mangaKey)
        #expect(manga.cover == "https://books.example.invalid/cover.png")
        #expect(manga.authors == ["Honbako"] && manga.status == .completed)
        #expect(manga.viewer == .unknown && manga.contentRating == .unknown)
        let updated = try await runner.getMangaUpdate(manga: manga, needsDetails: true, needsChapters: true)
        #expect(updated.status == .completed, "Chapter-only metadata must not erase fetched details")
        #expect(updated.authors == ["Honbako"])
        #expect(updated.chapters?.map(\.key) == ["/chapter/9", "/chapter/8"])
        #expect(updated.chapters?.map(\.language) == ["pt-BR", "pt-BR"])
        #expect(updated.chapters?.last?.chapterNumber == 8.5)
        #expect(updated.chapters?.first?.dateUploaded?.timeIntervalSince1970 == 1_793_030_400)
        #expect(updated.chapters?.last?.dateUploaded == nil)
        let requests = await transport.requests
        #expect(requests.map(\.operation) == [.discover, .search, .details, .chapters])
        #expect(requests.allSatisfy { $0.session.sourceId == sourceID })
        #expect(requests[1].page == 2 && requests[1].query == "Your First")
        #expect(requests.last?.manga?.url == mangaKey)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(requests[1])) as? [String: Any]
        #expect(json?["sourceId"] as? String == sourceID)
        #expect(json?["operation"] as? String == "search")
        #expect(json?["session"] == nil, "Requests use the frozen bridge's flat wire shape")
    }

    @Test("Page metadata stays lazy, preserves wire order and invokes extension image hooks one image at a time")
    func lazyPageImages() async throws {
        let transport = Transport(responses: [.pages: [success(pageRecords)]])
        let runner = try makeRunner(transport)
        let pages = try await runner.getPageList(manga: manga(), chapter: .init(key: chapterKey))
        #expect(pages.count == 3)
        #expect(await transport.imageRequests.isEmpty)
        var urls: [URL] = []
        for page in pages {
            guard case let .url(url, context) = page.content else { Issue.record("Pages must use the lazy runtime provider"); return }
            #expect(url.scheme == MihonRunner.imageScheme)
            #expect(url.host == "runtime")
            #expect(url.host != "books.example.invalid")
            urls.append(url)
            let payload = try await runner.runtimeImageData(url: url, context: context)
            #expect(payload.data == imageBytes(index: (await transport.imageRequests).last!.page.index))
        }
        #expect(Set(urls).count == 3)
        let images = await transport.imageRequests
        #expect(images.map(\.page.index) == [8, 1, 5], "Do not sort by extension Page.index")
        #expect(images[1].page.imageUrl == nil, "Image-URL resolution remains the runtime's responsibility")
        #expect(images[1].page.url == "https://books.example.invalid/reader/page-2")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(images[1])) as? [String: Any]
        #expect(encoded?["includeData"] as? Bool == true)
        #expect(encoded?["operation"] as? String == "image")
        #expect((encoded?["page"] as? [String: Any])?["imageUrl"] == nil)
        await expect(.imageLoaderRequired) {
            _ = try await runner.getImageRequest(url: urls[0].absoluteString, context: nil)
        }
    }

    @Test("Image contexts are issued by the runner and cannot be forged, crossed between editions or used as HTTP fallbacks")
    func imageContextIdentity() async throws {
        let transport = Transport(responses: [.pages: [success(pageRecords)]])
        let runner = try makeRunner(transport)
        let pages = try await runner.getPageList(manga: manga(), chapter: .init(key: chapterKey))
        guard case let .url(url, context) = pages[0].content else { Issue.record("Missing lazy page"); return }
        await expect(.invalidPageContext) { _ = try await runner.runtimeImageData(url: url, context: nil) }
        await expect(.invalidPageContext) {
            _ = try await runner.runtimeImageData(url: URL(string: "https://books.example.invalid/page.png")!, context: context)
        }
        let other = try makeRunner(transport, packageHash: String(repeating: "b", count: 64))
        await expect(.invalidPageContext) { _ = try await other.runtimeImageData(url: url, context: context) }
        let original = try #require(context?["honbako.mihon.page.v1"])
        var changed = try #require(JSONSerialization.jsonObject(with: Data(base64Encoded: original)!) as? [String: Any])
        changed["chapterKey"] = "/some-other-chapter"
        let data = try JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys])
        let forged = URL(string: "\(MihonRunner.imageScheme)://runtime/\(sourceID)/\(digest(data))")!
        await expect(.invalidPageContext) {
            _ = try await runner.runtimeImageData(url: forged, context: ["honbako.mihon.page.v1": data.base64EncodedString()])
        }
        #expect(await transport.imageRequests.isEmpty)
    }

    @Test("Wire failures, identity changes and duplicate chapter keys fail before altering local reading identity")
    func wireFailuresAndIdentity() async throws {
        let errorTransport = Transport(responses: [.search: [Data("{\"ok\":false,\"errorType\":\"ExampleFailure\",\"error\":\"Provider unavailable\"}".utf8)]])
        let errorRunner = try makeRunner(errorTransport)
        await expect(.extensionFailure(type: "ExampleFailure", message: "Provider unavailable")) {
            _ = try await errorRunner.getSearchMangaList(query: "a", page: 1, filters: [])
        }
        let wrongSource = Transport(discoveryID: "4508733312114627537")
        await expect(.identityMismatch) { _ = try await makeRunner(wrongSource).getSearchMangaList(query: "a", page: 1, filters: []) }
        #expect(await wrongSource.requests.map(\.operation) == [.discover])
        let moved = Transport(responses: [.details: [success("{\"manga\":{\"url\":\"/different-series\",\"title\":\"Changed\"},\"chapters\":[]}")]])
        await expect(.identityMismatch) { _ = try await makeRunner(moved).getMangaUpdate(manga: manga(), needsDetails: true, needsChapters: false) }
        let duplicate = Transport(responses: [.chapters: [success("""
          {"manga":{"url":"\(mangaKey)","title":"Original"},"chapters":[{"url":"/chapter/1","name":"A"},{"url":"/chapter/1","name":"B"}]}
          """)]])
        await expect(.invalidWireResponse) { _ = try await makeRunner(duplicate).getMangaUpdate(manga: manga(), needsDetails: false, needsChapters: true) }
        let malformed = Transport(responses: [.search: [Data("{\"ok\":true}".utf8)]])
        await expect(.invalidWireResponse) { _ = try await makeRunner(malformed).getSearchMangaList(query: "a", page: 1, filters: []) }
    }

    @Test("Source-wide all does not invent per-chapter translations or reader modes")
    func noInventedTranslations() async throws {
        let transport = Transport(responses: [.chapters: [success("""
          {"manga":{"url":"\(mangaKey)","title":"Original"},"chapters":[{"url":"/chapter/1","name":"Chapter","number":-1,"uploadedAt":0}]}
          """)]])
        let runner = try makeRunner(transport)
        let result = try await runner.getMangaUpdate(manga: manga(), needsDetails: false, needsChapters: true)
        #expect(result.chapters?.first?.language == nil)
        #expect(result.chapters?.first?.chapterNumber == nil)
        #expect(result.chapters?.first?.dateUploaded == nil)
        #expect(result.viewer == .unknown)
    }

    @Test("Invalid source requests and unsupported filters do not reach the runtime")
    func invalidInputs() async throws {
        let transport = Transport()
        let runner = try makeRunner(transport)
        await expect(.invalidInput) { _ = try await runner.getSearchMangaList(query: "a", page: 0, filters: []) }
        await expect(.unsupportedFilters) {
            _ = try await runner.getSearchMangaList(query: "a", page: 1, filters: [.text(id: "artist", value: "Example")])
        }
        let wrong = AidokuRunner.Manga(sourceKey: "some-other-source", key: mangaKey, title: "Original")
        await expect(.identityMismatch) { _ = try await runner.getPageList(manga: wrong, chapter: .init(key: chapterKey)) }
        #expect(await transport.requests.isEmpty)
        #expect(throws: MihonRuntimeError.invalidConfiguration) {
            _ = try MihonRunner.Configuration(extensionURL: URL(string: "https://example.invalid/remote.jar")!,
                packageName: "example.extension", versionName: "1.6.74", packageSHA256: String(repeating: "a", count: 64), sourceID: sourceID, language: "all")
        }
    }

    @Test("Malformed image bytes/metadata and oversized metadata responses are rejected")
    func payloadValidation() async throws {
        for payload in [MihonRuntimeImagePayload(data: Data()),
                        .init(data: Data([1, 2, 3]), reportedByteCount: 9),
                        .init(data: Data([1, 2, 3]), reportedSHA256: String(repeating: "0", count: 64)),
                        .init(data: Data([1, 2, 3]), mediaType: "text/html")] {
            let transport = Transport(responses: [.pages: [success(pageRecords)]], suppliedImage: payload)
            let runner = try makeRunner(transport)
            let pages = try await runner.getPageList(manga: manga(), chapter: .init(key: chapterKey))
            guard case let .url(url, context) = pages[0].content else { Issue.record("Missing lazy page"); return }
            await expect(.invalidImage) { _ = try await runner.runtimeImageData(url: url, context: context) }
        }
        let huge = Transport(responses: [.search: [Data(repeating: 0x20, count: MihonRunner.maximumMetadataBytes + 1)]])
        await expect(.payloadTooLarge) { _ = try await makeRunner(huge).getSearchMangaList(query: "a", page: 1, filters: []) }
        let unsafe = Transport(responses: [.search: [success("{\"hasNextPage\":false,\"entries\":[{\"url\":\"file:///private/secret\",\"title\":\"Unsafe\"}]}")]])
        await expect(.invalidWireResponse) { _ = try await makeRunner(unsafe).getSearchMangaList(query: "a", page: 1, filters: []) }
    }

    @Test("The image byte boundary is enforced after an otherwise successful extension image call")
    func imageSizeLimit() async throws {
        let transport = Transport(responses: [.pages: [success(pageRecords)]],
            suppliedImage: .init(data: Data(repeating: 0, count: MihonRunner.maximumImageBytes + 1)))
        let runner = try makeRunner(transport)
        let pages = try await runner.getPageList(manga: manga(), chapter: .init(key: chapterKey))
        guard case let .url(url, context) = pages[0].content else { Issue.record("Missing lazy page"); return }
        await expect(.payloadTooLarge) { _ = try await runner.runtimeImageData(url: url, context: context) }
    }

    @Test("Cancellation is observed before execution and after a noncooperative runtime returns")
    func cancellation() async throws {
        let transport = Transport()
        let runner = try makeRunner(transport)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await runner.getSearchMangaList(query: "a", page: 1, filters: [])
        }
        do { _ = try await cancelled.value; Issue.record("Cancelled source search must fail") }
        catch { #expect(error is CancellationError) }
        #expect(await transport.requests.isEmpty)

        let gate = Gate()
        let delayed = Transport(responses: [.search: [success("{\"hasNextPage\":false,\"entries\":[]}")]], gate: gate)
        let delayedRunner = try makeRunner(delayed)
        let task = Task { try await delayedRunner.getSearchMangaList(query: "a", page: 1, filters: []) }
        await gate.waitUntilStarted()
        task.cancel()
        await gate.release()
        do { _ = try await task.value; Issue.record("Cancelled runtime result must not be published") }
        catch { #expect(error is CancellationError) }
    }

    private func makeRunner(_ transport: Transport, language: String = "all", packageHash: String = String(repeating: "a", count: 64)) throws -> MihonRunner {
        let configuration = try MihonRunner.Configuration(extensionURL: URL(fileURLWithPath: "/verified/komga.jar"),
            packageName: "eu.kanade.tachiyomi.extension.all.komga", versionName: "1.6.74", packageSHA256: packageHash,
            sourceID: sourceID, language: language, baseURL: URL(string: "https://books.example.invalid/"), preferences: ["Address": "https://books.example.invalid"])
        return MihonRunner(configuration: configuration, transport: transport)
    }
    private func manga() -> AidokuRunner.Manga { .init(sourceKey: sourceKey, key: mangaKey, title: "Your First Chapter") }
    private var mangaRecord: String {
        "{\"url\":\"\(mangaKey)\",\"title\":\"Your First Chapter\",\"cover\":\"/cover.png\",\"author\":\"Honbako\",\"artist\":null,\"description\":\"Original content\",\"status\":2}"
    }
    private var pageRecords: String {
        """
        {"pages":[{"index":8,"url":"","imageUrl":"https://books.example.invalid/image-1.png"},{"index":1,"url":"https://books.example.invalid/reader/page-2","imageUrl":null},{"index":5,"url":"","imageUrl":"https://books.example.invalid/image-3.png"}]}
        """
    }
    private func success(_ result: String) -> Data { Data("{\"ok\":true,\"result\":\(result)}".utf8) }
    private func imageBytes(index: Int) -> Data { Data([0x89, 0x50, 0x4E, 0x47, UInt8(index)]) }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func expect(_ expected: MihonRuntimeError, _ operation: () async throws -> Void) async {
        do { try await operation(); Issue.record("Expected \(expected)") }
        catch { #expect(error as? MihonRuntimeError == expected) }
    }

    private actor Transport: MihonRuntimeTransport {
        private(set) var requests: [MihonRuntimeRequest] = []
        private(set) var imageRequests: [MihonRuntimeImageRequest] = []
        private var responses: [MihonRuntimeRequest.Operation: [Data]]
        private let discoveryID: String
        private let language: String
        private let suppliedImage: MihonRuntimeImagePayload?
        private let gate: Gate?
        init(language: String = "all", responses: [MihonRuntimeRequest.Operation: [Data]] = [:], discoveryID: String = "4508733312114627536",
             suppliedImage: MihonRuntimeImagePayload? = nil, gate: Gate? = nil) {
            self.responses = responses; self.discoveryID = discoveryID; self.language = language
            self.suppliedImage = suppliedImage; self.gate = gate
        }
        func execute(_ request: MihonRuntimeRequest) async throws -> Data {
            requests.append(request)
            if request.operation == .discover {
                return Data("{\"ok\":true,\"result\":{\"package\":\"eu.kanade.tachiyomi.extension.all.komga\",\"version\":\"1.6.74\",\"sources\":[{\"id\":\"\(discoveryID)\",\"name\":\"Komga\",\"language\":\"\(language)\"}]}}".utf8)
            }
            if request.operation == .search, let gate { await gate.pause() }
            guard var values = responses[request.operation], !values.isEmpty else { throw MihonRuntimeError.invalidInput }
            let next = values.removeFirst(); responses[request.operation] = values; return next
        }
        func imageData(_ request: MihonRuntimeImageRequest) async throws -> MihonRuntimeImagePayload {
            imageRequests.append(request)
            if let suppliedImage { return suppliedImage }
            let data = Data([0x89, 0x50, 0x4E, 0x47, UInt8(request.page.index)])
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return .init(data: data, mediaType: "image/png", reportedByteCount: data.count, reportedSHA256: digest)
        }
    }

    private actor Gate {
        private var started = false
        private var pending: CheckedContinuation<Void, Never>?
        private var observers: [CheckedContinuation<Void, Never>] = []
        func pause() async {
            started = true
            for observer in observers { observer.resume() }
            observers = []
            await withCheckedContinuation { pending = $0 }
        }
        func waitUntilStarted() async {
            if !started { await withCheckedContinuation { observers.append($0) } }
        }
        func release() { pending?.resume(); pending = nil }
    }
}
