@testable import Sumi
import AidokuRunner
import Foundation
import Testing

struct HonbakoMihonImageMIMEValidationTests {
    private let sourceID = "4508733312114627536"
    private let sourceKey = "mihon.4508733312114627536"
    private let imageURL = URL(string: "https://books.example.invalid/image.png")!

    @Test("Image MIME controls are rejected as Unicode scalars at every byte boundary, including the single CRLF grapheme",
          arguments: ["\r\n", "\r", "\n", "\t", "\u{0000}", "\u{007F}"])
    func controlsFailAtEveryBoundary(_ control: String) async throws {
        let payload = MihonRuntimeImagePayload(data: Data([0x89, 0x50, 0x4E, 0x47]), mediaType: "image/png\(control)Injected: 1")
        let session = MihonRuntimeSession(extensionPath: "/reviewed/komga.jar", sourceId: sourceID, preferences: [:])
        let transport = MihonJSONRuntimeTransport(executeJSON: { _ in "{}" }, imageBytes: { _ in payload })
        await expectInvalidImage {
            _ = try await transport.imageData(.init(session: session, page: .init(index: 0, url: "", imageUrl: imageURL.absoluteString)))
        }
        await expectInvalidImage { _ = try await transport.coverData(session: session, url: imageURL) }

        // The typed transport is independently injectable, so the Runner must
        // also reject bad MIME rather than rely on a specific JSON executor.
        let runner = MihonRunner(configuration: try .init(extensionURL: URL(fileURLWithPath: session.extensionPath),
            packageName: "example.extension", versionName: "1.6.1", packageSHA256: String(repeating: "a", count: 64),
            sourceID: sourceID, language: "en"), transport: Transport(payload: payload))
        let pages = try await runner.getPageList(manga: .init(sourceKey: sourceKey, key: "/series/original", title: "Original"),
            chapter: .init(key: "/books/1"))
        guard case let .url(url, context) = try #require(pages.first).content else { Issue.record("Missing runtime page"); return }
        await expectInvalidImage { _ = try await runner.runtimeImageData(url: url, context: context) }
        await expectInvalidImage { _ = try await runner.runtimeCoverData(url: imageURL) }

        // Protocol providers can be supplied without MihonRunner. Both loader
        // helpers keep their own byte boundary for those implementations.
        let provider = Provider(payload: payload)
        let source = AidokuRunner.Source(key: sourceKey, name: "Fixture", version: 1, contentRating: .safe, runner: provider)
        let opaque = URL(string: "honbako-mihon-page://runtime/\(sourceID)/\(String(repeating: "a", count: 64))")!
        await expectInvalidImage { _ = try await MihonRuntimeImageLoader.imageData(url: opaque, context: ["fixture": "page"], source: source) }
        await expectInvalidImage { _ = try await MihonRuntimeCoverImageLoader.imageData(url: imageURL, source: source) }
    }

    private func expectInvalidImage(_ operation: () async throws -> Void) async {
        do { try await operation(); Issue.record("Control-bearing MIME was accepted") }
        catch { #expect(error as? MihonRuntimeError == .invalidImage) }
    }

    private struct Transport: MihonRuntimeCoverTransport {
        let payload: MihonRuntimeImagePayload
        func execute(_ request: MihonRuntimeRequest) async throws -> Data {
            switch request.operation {
            case .discover:
                Data("{\"ok\":true,\"result\":{\"package\":\"example.extension\",\"version\":\"1.6.1\",\"sources\":[{\"id\":\"4508733312114627536\",\"name\":\"Fixture\",\"language\":\"en\"}]}}".utf8)
            case .pages:
                Data("{\"ok\":true,\"result\":{\"pages\":[{\"index\":0,\"url\":\"\",\"imageUrl\":\"https://books.example.invalid/image.png\"}]}}".utf8)
            default: throw MihonRuntimeError.invalidInput
            }
        }
        func imageData(_ request: MihonRuntimeImageRequest) async throws -> MihonRuntimeImagePayload { payload }
        func coverData(session: MihonRuntimeSession, url: URL) async throws -> MihonRuntimeImagePayload { payload }
    }

    private actor Provider: AidokuRunner.Runner, MihonRuntimeImageProviding, MihonRuntimeCoverImageProviding {
        nonisolated let features = AidokuRunner.SourceFeatures(providesImageRequests: true)
        nonisolated let runtimeCoverSourceKey = "mihon.4508733312114627536"
        nonisolated let runtimeCoverCacheScope = "mime-control-fixture"
        let payload: MihonRuntimeImagePayload
        init(payload: MihonRuntimeImagePayload) { self.payload = payload }
        func runtimeImageData(url: URL, context: AidokuRunner.PageContext?) async throws -> MihonRuntimeImagePayload { payload }
        func runtimeCoverData(url: URL) async throws -> MihonRuntimeImagePayload { payload }
        func getImageRequest(url: String, context: AidokuRunner.PageContext?) async throws -> URLRequest { throw MihonRuntimeError.imageLoaderRequired }
        func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult { .init(entries: [], hasNextPage: false) }
        func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga { manga }
        func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] { [] }
    }
}
