@testable import Sumi
import CryptoKit
import Foundation
import Testing

struct HonbakoMihonJSONTransportTests {
    private let session = MihonRuntimeSession(extensionPath: "/reviewed/komga.jar", sourceId: "4508733312114627536",
        preferences: ["Address": "https://books.example.invalid", "Unicode": "漫畫"])

    @Test("The native JSON executor receives the actual flat bridge wire format with exact 64-bit source IDs")
    func flatMetadataWire() async throws {
        let calls = Calls()
        let response = "{\"ok\":true,\"result\":{\"entries\":[],\"hasNextPage\":false}}"
        let transport = MihonJSONRuntimeTransport(executeJSON: { input in
            await calls.append(input, image: false)
            return response
        }, imageBytes: { _ in throw Failure.unexpectedImageCall })
        let requests: [MihonRuntimeRequest] = [
            .init(session: session, operation: .discover),
            .init(session: session, operation: .search, query: "漫畫 \"Original\"", page: 2),
            .init(session: session, operation: .details, manga: .init(url: "/series/original", title: "Original")),
            .init(session: session, operation: .chapters, manga: .init(url: "/series/original", title: "Original")),
            .init(session: session, operation: .pages, chapter: .init(url: "/books/1", name: "First"))
        ]
        for request in requests {
            #expect(try await transport.execute(request) == Data(response.utf8))
        }
        let inputs = await calls.metadata
        #expect(inputs.count == 5)
        for (input, request) in zip(inputs, requests) {
            let fields = try object(input)
            #expect(fields["sourceId"] as? String == session.sourceId)
            #expect(fields["extensionPath"] as? String == session.extensionPath)
            #expect(fields["preferences"] as? [String: String] == session.preferences)
            #expect(fields["operation"] as? String == request.operation.rawValue)
            #expect(fields["session"] == nil)
        }
        let search = try object(inputs[1])
        #expect(search["query"] as? String == "漫畫 \"Original\"")
        #expect(search["page"] as? Int == 2)
        #expect((try object(inputs[4])["chapter"] as? [String: Any])?["url"] as? String == "/books/1")
    }

    @Test("Page and cover bytes use the binary executor; unresolved image URLs stay unresolved in the request")
    func imageAndCoverWire() async throws {
        let calls = Calls()
        let payload = imagePayload()
        let transport = MihonJSONRuntimeTransport(executeJSON: { _ in throw Failure.unexpectedMetadataCall }, imageBytes: { input in
            await calls.append(input, image: true)
            return payload
        })
        let request = MihonRuntimeImageRequest(session: session,
            page: .init(index: 7, url: "https://books.example.invalid/reader/7", imageUrl: nil))
        #expect(try await transport.imageData(request) == payload)
        let coverURL = URL(string: "https://books.example.invalid/covers/1.jpg?edition=2")!
        #expect(try await transport.coverData(session: session, url: coverURL) == payload)
        let images = await calls.images
        #expect(images.count == 2)
        let page = try object(images[0])
        #expect(page["operation"] as? String == "image")
        #expect(page["includeData"] as? Bool == true)
        let descriptor = try #require(page["page"] as? [String: Any])
        #expect(descriptor["index"] as? Int == 7)
        #expect(descriptor["url"] as? String == request.page.url)
        #expect(descriptor["imageUrl"] == nil)
        let cover = try object(images[1])
        #expect(cover["operation"] as? String == "cover")
        #expect(cover["url"] as? String == coverURL.absoluteString)
        #expect(cover["page"] == nil && cover["includeData"] == nil)
        #expect(cover["sourceId"] as? String == session.sourceId)
        #expect(await calls.metadata.isEmpty)
    }

    @Test("A reviewed package binding accompanies every operation and rejects an extension path change before native execution")
    func packageBinding() async throws {
        let calls = Calls()
        let identity = try MihonJSONRuntimeTransport.PackageIdentity(extensionPath: session.extensionPath,
            packageSHA256: String(repeating: "a", count: 64), packageName: "eu.kanade.tachiyomi.extension.all.komga", versionName: "1.6.74")
        let payload = imagePayload()
        let transport = MihonJSONRuntimeTransport(packageIdentity: identity, executeJSON: { input in
            await calls.append(input, image: false); return "{}"
        }, imageBytes: { input in await calls.append(input, image: true); return payload })
        _ = try await transport.execute(.init(session: session, operation: .discover))
        _ = try await transport.imageData(.init(session: session, page: .init(index: 0, url: "", imageUrl: "https://books.example.invalid/image.png")))
        _ = try await transport.coverData(session: session, url: URL(string: "https://books.example.invalid/cover.png")!)
        let inputs = await calls.metadata + calls.images
        for input in inputs {
            let fields = try object(input)
            #expect(fields["packageSHA256"] as? String == identity.packageSHA256)
            #expect(fields["packageName"] as? String == identity.packageName)
            #expect(fields["versionName"] as? String == identity.versionName)
            #expect(fields["extensionLibrary"] as? String == "1.6")
        }
        let different = MihonRuntimeSession(extensionPath: "/unreviewed/other.jar", sourceId: session.sourceId, preferences: [:])
        await expect(.identityMismatch) { _ = try await transport.execute(.init(session: different, operation: .discover)) }
        #expect(await calls.metadata.count == 1)
        #expect(throws: MihonRuntimeError.invalidConfiguration) {
            _ = try MihonJSONRuntimeTransport.PackageIdentity(extensionPath: session.extensionPath,
                packageSHA256: String(repeating: "a", count: 64), packageName: "example.extension", versionName: "2", extensionLibrary: "1.5")
        }
    }

    @Test("Callback errors retain their original type instead of becoming source or JSON errors")
    func callbackErrors() async throws {
        let transport = MihonJSONRuntimeTransport(executeJSON: { _ in throw Failure.executorFailure }, imageBytes: { _ in throw Failure.executorFailure })
        do { _ = try await transport.execute(.init(session: session, operation: .discover)); Issue.record("Missing executor failure") }
        catch { #expect(error as? Failure == .executorFailure) }
        do { _ = try await transport.imageData(validImageRequest()); Issue.record("Missing image executor failure") }
        catch { #expect(error as? Failure == .executorFailure) }
    }

    @Test("Invalid operation shapes, native page integers and source identities never reach either executor")
    func preflightValidation() async throws {
        let calls = Calls()
        let payload = imagePayload()
        let transport = MihonJSONRuntimeTransport(executeJSON: { input in await calls.append(input, image: false); return "{}" },
            imageBytes: { input in await calls.append(input, image: true); return payload })
        for invalid in [MihonRuntimeRequest(session: session, operation: .search, query: "a", page: 0),
                        .init(session: session, operation: .search, query: "a", page: Int(Int32.max) + 1),
                        .init(session: session, operation: .discover, query: "extra"),
                        .init(session: session, operation: .details),
                        .init(session: session, operation: .pages, chapter: .init(url: "file:///private/file", name: "Unsafe"))] {
            await expect(.invalidInput) { _ = try await transport.execute(invalid) }
        }
        for sourceID in ["4508733312114627536.0", "9223372036854775808", "04508733312114627536"] {
            let invalid = MihonRuntimeSession(extensionPath: session.extensionPath, sourceId: sourceID, preferences: [:])
            await expect(.invalidConfiguration) { _ = try await transport.execute(.init(session: invalid, operation: .discover)) }
        }
        for page in [MihonRuntimePageRecord(index: -1, url: "https://books.example.invalid/page", imageUrl: nil),
                     .init(index: 0, url: "", imageUrl: nil),
                     .init(index: 0, url: "", imageUrl: "https://user:secret@books.example.invalid/image")] {
            await expect(.invalidInput) { _ = try await transport.imageData(.init(session: session, page: page)) }
        }
        await expect(.invalidInput) { _ = try await transport.coverData(session: session, url: URL(fileURLWithPath: "/cover.png")) }
        #expect(await calls.metadata.isEmpty)
        #expect(await calls.images.isEmpty)
    }

    @Test("Both aggregate preference size and JSON escaping/UTF-16 expansion are bounded before native allocation")
    func requestBounds() async throws {
        let calls = Calls()
        let transport = MihonJSONRuntimeTransport(executeJSON: { input in await calls.append(input, image: false); return "{}" },
            imageBytes: { _ in throw Failure.unexpectedImageCall })
        let dictionaries = [
            Dictionary(uniqueKeysWithValues: (0..<80).map { ("key\($0)", String(repeating: "a", count: 16_384)) }),
            Dictionary(uniqueKeysWithValues: (0..<48).map { ("key\($0)", String(repeating: "\u{0001}", count: 16_384)) }),
            Dictionary(uniqueKeysWithValues: (0..<33).map { ("key\($0)", String(repeating: "a", count: 16_384)) })
        ]
        for preferences in dictionaries {
            let oversized = MihonRuntimeSession(extensionPath: session.extensionPath, sourceId: session.sourceId, preferences: preferences)
            await expect(.payloadTooLarge) { _ = try await transport.execute(.init(session: oversized, operation: .discover)) }
        }
        #expect(await calls.metadata.isEmpty)
    }

    @Test("Metadata is bounded in UTF-8 bytes and native UTF-16 units before publication")
    func responseBounds() async throws {
        for response in [String(repeating: "a", count: MihonJSONRuntimeTransport.maximumResponseUTF16Units + 1),
                         String(repeating: "漢", count: MihonJSONRuntimeTransport.maximumMetadataBytes / 3 + 1)] {
            let transport = MihonJSONRuntimeTransport(executeJSON: { _ in response }, imageBytes: { _ in throw Failure.unexpectedImageCall })
            await expect(.payloadTooLarge) { _ = try await transport.execute(.init(session: session, operation: .discover)) }
        }
    }

    @Test("The binary result boundary rejects empty, oversized and mismatched image payloads")
    func imageBounds() async throws {
        let bytes = imagePayload().data
        for payload in [MihonRuntimeImagePayload(data: Data()),
                        .init(data: bytes, reportedByteCount: bytes.count + 1),
                        .init(data: bytes, reportedSHA256: String(repeating: "0", count: 64)),
                        .init(data: bytes, mediaType: "text/html"),
                        .init(data: bytes, mediaType: "image/png\r\nInjected: 1")] {
            let transport = MihonJSONRuntimeTransport(executeJSON: { _ in "{}" }, imageBytes: { _ in payload })
            await expect(.invalidImage) { _ = try await transport.imageData(validImageRequest()) }
        }
        let oversized = MihonRuntimeImagePayload(data: Data(repeating: 0, count: MihonJSONRuntimeTransport.maximumImageBytes + 1))
        let transport = MihonJSONRuntimeTransport(executeJSON: { _ in "{}" }, imageBytes: { _ in oversized })
        await expect(.payloadTooLarge) { _ = try await transport.imageData(validImageRequest()) }
    }

    @Test("Cancellation before execution and after a noncooperative JSON callback prevents late metadata publication")
    func metadataCancellation() async throws {
        let calls = Calls()
        let gate = Gate()
        let transport = MihonJSONRuntimeTransport(executeJSON: { input in
            await calls.append(input, image: false); await gate.pause(); return "{}"
        }, imageBytes: { _ in throw Failure.unexpectedImageCall })
        let early = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await transport.execute(.init(session: session, operation: .discover))
        }
        await expectCancellation(early)
        #expect(await calls.metadata.isEmpty)
        let late = Task { try await transport.execute(.init(session: session, operation: .discover)) }
        await gate.waitUntilStarted()
        late.cancel()
        await gate.release()
        await expectCancellation(late)
        #expect(await calls.metadata.count == 1)
    }

    @Test("A noncooperative binary callback cannot publish an image after cancellation")
    func imageCancellation() async throws {
        let gate = Gate()
        let payload = imagePayload()
        let transport = MihonJSONRuntimeTransport(executeJSON: { _ in throw Failure.unexpectedMetadataCall }, imageBytes: { _ in
            await gate.pause(); return payload
        })
        let task = Task { try await transport.imageData(validImageRequest()) }
        await gate.waitUntilStarted()
        task.cancel()
        await gate.release()
        await expectCancellation(task)
    }

    @Test("The Runner validates real error envelopes returned unchanged by the JSON transport")
    func runnerEnvelopeValidation() async throws {
        let calls = Calls()
        let transport = MihonJSONRuntimeTransport(executeJSON: { input in
            await calls.append(input, image: false)
            if input.contains("\"operation\":\"discover\"") {
                return "{\"ok\":true,\"result\":{\"package\":\"example.extension\",\"version\":\"1.6.1\",\"sources\":[{\"id\":\"4508733312114627536\",\"name\":\"Example\",\"language\":\"en\"}]}}"
            }
            return "{\"ok\":false,\"errorType\":\"ProviderFailure\",\"error\":\"Unavailable\"}"
        }, imageBytes: { _ in throw Failure.unexpectedImageCall })
        let configuration = try MihonRunner.Configuration(extensionURL: URL(fileURLWithPath: session.extensionPath),
            packageName: "example.extension", versionName: "1.6.1", packageSHA256: String(repeating: "a", count: 64), sourceID: session.sourceId, language: "en")
        let runner = MihonRunner(configuration: configuration, transport: transport)
        await expect(.extensionFailure(type: "ProviderFailure", message: "Unavailable")) {
            _ = try await runner.getSearchMangaList(query: "Original", page: 1, filters: [])
        }
        #expect(await calls.metadata.count == 2)
    }

    private func validImageRequest() -> MihonRuntimeImageRequest {
        .init(session: session, page: .init(index: 0, url: "", imageUrl: "https://books.example.invalid/image.png"))
    }
    private func imagePayload() -> MihonRuntimeImagePayload {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return .init(data: bytes, mediaType: "image/png", reportedByteCount: bytes.count, reportedSHA256: digest)
    }
    private func object(_ input: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
    }
    private func expect(_ expected: MihonRuntimeError, _ operation: () async throws -> Void) async {
        do { try await operation(); Issue.record("Expected \(expected)") }
        catch { #expect(error as? MihonRuntimeError == expected) }
    }
    private func expectCancellation<Value: Sendable>(_ task: Task<Value, Error>) async {
        do { _ = try await task.value; Issue.record("Cancelled result was published") }
        catch { #expect(error is CancellationError) }
    }
    private enum Failure: Error, Equatable { case executorFailure, unexpectedMetadataCall, unexpectedImageCall }
    private actor Calls {
        private(set) var metadata: [String] = []
        private(set) var images: [String] = []
        func append(_ input: String, image: Bool) {
            if image { images.append(input) } else { metadata.append(input) }
        }
    }
    private actor Gate {
        private var started = false
        private var startedWaiters: [CheckedContinuation<Void, Never>] = []
        private var waiting: CheckedContinuation<Void, Never>?
        func pause() async {
            await withCheckedContinuation { continuation in
                started = true
                waiting = continuation
                startedWaiters.forEach { $0.resume() }
                startedWaiters.removeAll()
            }
        }
        func waitUntilStarted() async {
            if started { return }
            await withCheckedContinuation { startedWaiters.append($0) }
        }
        func release() { waiting?.resume(); waiting = nil }
    }
}
