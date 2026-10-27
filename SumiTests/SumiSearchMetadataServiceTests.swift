@testable import Sumi
import AidokuRunner
import Foundation
import Testing

struct SumiSearchMetadataServiceTests {
    private static let id = UUID(uuidString: "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb")!

    @Test("Exact MangaDex response supplies release year and author expansion")
    func decodeExactMetadata() throws {
        let data = Self.response(id: Self.id, year: "2009")
        let value = try SumiSearchMetadataService.decode(data, requestedID: Self.id)
        #expect(value.releaseYear == 2009)
        #expect(value.authors == ["Source Author"])
        #expect(throws: URLError.self) {
            try SumiSearchMetadataService.decode(data, requestedID: UUID())
        }
        let missing = try SumiSearchMetadataService.decode(Self.response(id: Self.id, year: "null"), requestedID: Self.id)
        #expect(missing.releaseYear == nil)
    }

    @Test("Title translation languages come from chapter availability, never the original publication language")
    func titleTranslationLanguages() throws {
        let data = Data("""
        {"result":"ok","data":{"id":"\(Self.id.uuidString)","type":"manga",
        "attributes":{"originalLanguage":"ja","availableTranslatedLanguages":["en","pt-br",null]}}}
        """.utf8)
        let value = try SumiSearchMetadataService.decode(data, requestedID: Self.id)
        #expect(value.translatedLanguages == ["en", "pt-br"])
        let originalOnly = Data("""
        {"result":"ok","data":{"id":"\(Self.id.uuidString)","type":"manga",
        "attributes":{"originalLanguage":"ja"}}}
        """.utf8)
        #expect(try SumiSearchMetadataService.decode(originalOnly, requestedID: Self.id).translatedLanguages.isEmpty)
    }

    @Test("Publication metadata distinguishes completed, ongoing, paused, and cancelled titles")
    func publicationStatus() throws {
        let statuses: [(String, AidokuRunner.PublishingStatus)] = [
            ("ongoing", .ongoing), ("completed", .completed), ("hiatus", .hiatus), ("cancelled", .cancelled)
        ]
        for (status, expected) in statuses {
            let data = Self.response(id: Self.id, year: "2009", status: status)
            let value = try SumiSearchMetadataService.decode(data, requestedID: Self.id)
            #expect(value.publishingStatus == expected)
            #expect(value.isOngoing == (expected == .ongoing))
        }
        for status in [nil, "unknown", "future-status"] as [String?] {
            let data = Self.response(id: Self.id, year: "2009", status: status)
            let value = try SumiSearchMetadataService.decode(data, requestedID: Self.id)
            #expect(value.isOngoing == nil, "A missing or unfamiliar status must not imply an ongoing publication")
            #expect(value.publishingStatus == nil, "An unknown status must not be presented as Finished")
        }
        let nullStatus = Data("""
        {"result":"ok","data":{"id":"\(Self.id.uuidString)","type":"manga",
        "attributes":{"year":null,"status":null}}}
        """.utf8)
        #expect(try SumiSearchMetadataService.decode(nullStatus, requestedID: Self.id).isOngoing == nil)
        #expect(try SumiSearchMetadataService.decode(nullStatus, requestedID: Self.id).publishingStatus == nil)
    }

    @Test("Only the connected MangaDex source's exact ID or official title URL is eligible")
    func exactSourceIdentity() {
        let known = AidokuRunner.Manga(sourceKey: "multi.mangadex", key: Self.id.uuidString, title: "Title")
        #expect(SumiSearchMetadataService.mangaID(for: SumiBook(manga: known)) == Self.id)
        let native = AidokuRunner.Manga(sourceKey: "honbako.mangadex", key: Self.id.uuidString, title: "Title")
        #expect(SumiSearchMetadataService.mangaID(for: SumiBook(manga: native)) == Self.id)
        let unrelated = AidokuRunner.Manga(sourceKey: "other.source", key: Self.id.uuidString, title: "Same Title")
        #expect(SumiSearchMetadataService.mangaID(for: SumiBook(manga: unrelated)) == nil)
        var title = AidokuRunner.Manga(sourceKey: "multi.mangadex", key: "slug", title: "Title")
        title.url = URL(string: "https://mangadex.org/title/\(Self.id.uuidString)/title")
        #expect(SumiSearchMetadataService.mangaID(for: SumiBook(manga: title)) == Self.id)
        title.url = URL(string: "https://unrelated.example/title/\(Self.id.uuidString)/title")
        #expect(SumiSearchMetadataService.mangaID(for: SumiBook(manga: title)) == nil)
    }

    @Test("Concurrent appearances share a cached exact-title request")
    func requestDeduplication() async {
        let probe = Probe(data: Self.response(id: Self.id, year: "2009", status: "ongoing"))
        let service = SumiSearchMetadataService(loader: { try await probe.load($0) })
        let book = SumiBook(manga: .init(sourceKey: "multi.mangadex", key: Self.id.uuidString, title: "Title"))
        async let first = service.metadata(for: book)
        async let duplicate = service.metadata(for: book)
        let values = await [first, duplicate]
        #expect(values.allSatisfy { $0?.releaseYear == 2009 })
        #expect(values.allSatisfy { $0?.isOngoing == true })
        #expect(values.allSatisfy { $0?.publishingStatus == .ongoing })
        #expect(await probe.count == 1)
        #expect(await service.metadata(for: book)?.authors == ["Source Author"])
        #expect(await probe.count == 1)
        let request = await probe.lastRequest
        #expect(request?.url?.host == "api.mangadex.org")
        #expect(request?.url?.path == "/manga/\(Self.id.uuidString.lowercased())")
        #expect(request?.url?.query?.contains("author") == true)
    }

    @Test("Unavailable metadata is cached briefly instead of retrying on every row update")
    func failureCache() async {
        let probe = Probe(data: Data(), status: 404)
        let service = SumiSearchMetadataService(loader: { try await probe.load($0) })
        let book = SumiBook(manga: .init(sourceKey: "multi.mangadex", key: Self.id.uuidString, title: "Title"))
        #expect(await service.metadata(for: book) == nil)
        #expect(await service.metadata(for: book) == nil)
        #expect(await probe.count == 1)
    }

    @Test("Canceling a vanished row cancels its request without caching a missing result")
    func canceledRow() async throws {
        let probe = Probe(data: Self.response(id: Self.id, year: "2009"))
        let service = SumiSearchMetadataService(loader: { try await probe.load($0) })
        let book = SumiBook(manga: .init(sourceKey: "multi.mangadex", key: Self.id.uuidString, title: "Title"))
        let request = Task { await service.metadata(for: book) }
        while await probe.count == 0 { try await Task.sleep(for: .milliseconds(5)) }
        request.cancel()
        #expect(await request.value == nil)
        #expect(await service.metadata(for: book)?.releaseYear == 2009)
        #expect(await probe.count == 2)
    }

    @Test("A provider rate limit pauses metadata for other rows too")
    func providerCooldown() async {
        let probe = Probe(data: Data(), status: 429)
        let service = SumiSearchMetadataService(loader: { try await probe.load($0) })
        let first = SumiBook(manga: .init(sourceKey: "multi.mangadex", key: Self.id.uuidString, title: "Title"))
        let other = SumiBook(manga: .init(sourceKey: "multi.mangadex", key: UUID().uuidString, title: "Other"))
        #expect(await service.metadata(for: first) == nil)
        #expect(await service.metadata(for: other) == nil)
        #expect(await probe.count == 1)
    }

    private static func response(id: UUID, year: String, status: String? = nil) -> Data {
        let statusAttribute = status.map { ", \"status\": \"\($0)\"" } ?? ""
        return Data("""
        {"result":"ok","data":{"id":"\(id.uuidString)","type":"manga","attributes":{"year":\(year)\(statusAttribute)},
        "relationships":[{"type":"author","attributes":{"name":" Source Author "}},
        {"type":"author","attributes":{"name":"Source Author"}},
        {"type":"artist","attributes":{"name":"Different Artist"}}]}}
        """.utf8)
    }

    private actor Probe {
        let data: Data
        let status: Int
        var count = 0
        var lastRequest: URLRequest?
        init(data: Data, status: Int = 200) { self.data = data; self.status = status }
        func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            count += 1
            lastRequest = request
            try await Task.sleep(for: .milliseconds(80))
            return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}
