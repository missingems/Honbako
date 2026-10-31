@testable import Sumi
import AidokuRunner
import Foundation
import Testing

@Suite(.serialized)
struct HonbakoMangaDexRunnerTests {
    private let mangaID = "11111111-1111-4111-8111-111111111111"
    private let chapterID = "22222222-2222-4222-8222-222222222222"

    @Test("A prepared native result has author, year, status and a real readable probe without a fake complete chapter list")
    func completeSearchPreparation() async throws {
        let name = "Honbako.NativeSearch.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let title = try titleData(collection: true)
        let feed = try collection([chapter()], total: 1, offset: 0)
        let requests = RequestRecorder()
        let runner = HonbakoMangaDexRunner(defaults: defaults, requestInterval: .zero) { request in
            await requests.record(request)
            let data = request.url?.path == "/manga" ? title : feed
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let results = try await runner.getSearchMangaList(query: "Fixture", page: 1, filters: [])
        let manga = try #require(results.entries.first)
        let prepared = try await runner.prepareSearchResult(manga)
        #expect(prepared.manga.authors == ["Fixture Author"])
        #expect(prepared.manga.status == .completed)
        #expect(prepared.manga.viewer == .rightToLeft)
        #expect(prepared.releaseYear == 1998)
        #expect(prepared.translatedLanguages == ["en", "es-419", "zh-hans"])
        #expect(prepared.readableChapter?.key == chapterID)
        #expect(prepared.manga.chapters == nil)
        _ = try await runner.prepareSearchResult(manga)
        let urls = await requests.urls
        #expect(urls.count == 2, "Search details and repeated probes must reuse cached metadata")
        let parameters = URLComponents(url: try #require(urls.last), resolvingAgainstBaseURL: false)?.queryItems ?? []
        for name in ["includeEmptyPages", "includeExternalUrl", "includeFutureUpdates", "includeFuturePublishAt", "includeUnavailable"] {
            #expect(parameters.first(where: { $0.name == name })?.value == "0")
        }
        #expect(parameters.first(where: { $0.name == "limit" })?.value == "1")
        #expect(parameters.first(where: { $0.name == "translatedLanguage[]" })?.value == "en")
    }

    @Test("Chapter menus retain confirmed external, empty and future entries as unavailable without changing languages")
    func realTranslationChaptersOnly() async throws {
        let name = "Honbako.NativeLanguages.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["en"], forKey: HonbakoMangaDexRunner.sourceKey + ".languages")
        let data = try collection([
            chapter(language: "es-la"),
            chapter(id: "33333333-3333-4333-8333-333333333333", external: "https://publisher.example/chapter"),
            chapter(id: "44444444-4444-4444-8444-444444444444", pages: 0),
            chapter(id: "55555555-5555-4555-8555-555555555555", publishAt: "2100-01-01T00:00:00Z")
        ], total: 4, offset: 0)
        let requests = RequestRecorder()
        let runner = HonbakoMangaDexRunner(defaults: defaults, requestInterval: .zero) { request in
            await requests.record(request)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let chapters = try await runner.chapters(for: manga(), language: "es-419")
        #expect(chapters.count == 4)
        #expect(chapters.first?.key == chapterID)
        #expect(chapters.first?.locked == false)
        let unavailableAreLocked = chapters.dropFirst().allSatisfy { $0.locked }
        #expect(unavailableAreLocked)
        #expect(chapters.first?.language == "es-419")
        #expect(defaults.stringArray(forKey: HonbakoMangaDexRunner.sourceKey + ".languages") == ["en"])
        let parameters = URLComponents(url: try #require(await requests.urls.first), resolvingAgainstBaseURL: false)?.queryItems
        #expect(parameters?.first(where: { $0.name == "translatedLanguage[]" })?.value == "es-la")
    }

    #if HONBAKO_EXTERNAL_SOURCES
    @Test("Alternative recovery requests one bounded oldest readable feed without changing configured languages")
    func boundedAlternativeEditionFeed() async throws {
        let name = "Honbako.AlternativeEdition.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["en"], forKey: HonbakoMangaDexRunner.sourceKey + ".languages")
        let az = chapter(language: "az")
        let huID = "33333333-3333-4333-8333-333333333333"
        let data = try collection([az,
            chapter(id: huID, language: "hu"), az,
            chapter(id: "44444444-4444-4444-8444-444444444444", pages: 0),
            chapter(id: "55555555-5555-4555-8555-555555555555", external: "https://publisher.example/chapter"),
            chapter(id: "66666666-6666-4666-8666-666666666666", publishAt: "2100-01-01T00:00:00Z"),
            chapter(id: "invalid")], total: 500, offset: 0)
        let requests = RequestRecorder()
        let runner = HonbakoMangaDexRunner(defaults: defaults, requestInterval: .zero, transport: { request in
            await requests.record(request)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let chapters = try await runner.readableAlternativeChapters(for: manga())
        #expect(chapters.map(\.key) == [huID, chapterID])
        #expect(chapters.map(\.language) == ["hu", "az"])
        let urls = await requests.urls
        #expect(urls.count == 1, "This recovery must not paginate every translation")
        let query = URLComponents(url: try #require(urls.first), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(!query.contains { $0.name == "translatedLanguage[]" })
        #expect(query.first { $0.name == "limit" }?.value == "100")
        #expect(query.first { $0.name == "offset" }?.value == "0")
        for field in ["includeEmptyPages", "includeExternalUrl", "includeUnavailable", "includeFutureUpdates", "includeFuturePublishAt"] {
            #expect(query.first { $0.name == field }?.value == "0")
        }
        #expect(query.first { $0.name == "order[volume]" }?.value == "asc")
        #expect(query.first { $0.name == "order[chapter]" }?.value == "asc")
        #expect(defaults.stringArray(forKey: HonbakoMangaDexRunner.sourceKey + ".languages") == ["en"])
    }
    #endif

    @Test("The official Long Strip format tag preserves vertical reading")
    func longStripUsesVerticalReader() throws {
        let data = try titleData(collection: false, longStrip: true)
        let response = try JSONDecoder().decode(HonbakoMangaDexAPI.Entity<HonbakoMangaDexAPI.Title>.self, from: data)
        #expect(response.data.manga(preferredLanguages: ["en"]).viewer == .webtoon)
    }

    @Test("Chapter pagination follows the actual response and retains every real page group")
    func paginatedChapterCollection() async throws {
        let first = try collection([
            chapter(),
            chapter(id: "33333333-3333-4333-8333-333333333333")
        ], total: 3, offset: 0)
        let second = try collection([chapter(id: "44444444-4444-4444-8444-444444444444")], total: 3, offset: 2)
        let requests = RequestRecorder()
        let runner = HonbakoMangaDexRunner(requestInterval: .zero) { request in
            await requests.record(request)
            let offset = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "offset" }?.value
            return (offset == "0" ? first : second,
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let chapters = try await runner.chapters(for: manga(), language: "en")
        #expect(chapters.count == 3)
        #expect(Set(chapters.map(\.key)).count == 3)
        #expect(await requests.urls.count == 2)
    }

    @Test("A confirmed title language outside the reviewed catalog, such as Khmer, can load")
    func titleReportedKhmerBeyondCatalog() async throws {
        let details = try titleData(collection: false, languages: ["en", "km"])
        let feed = try collection([chapter(language: "km")], total: 1, offset: 0)
        let requests = RequestRecorder()
        let runner = HonbakoMangaDexRunner(requestInterval: .zero) { request in
            await requests.record(request)
            let data = request.url?.path.hasSuffix("/feed") == true ? feed : details
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(!HonbakoMangaDexRunner.languages.contains("km"))
        #expect(try await runner.availableLanguages(for: manga()) == ["en", "km"])
        let chapters = try await runner.chapters(for: manga(), language: "km")
        #expect(chapters.first?.language == "km")
        #expect(await requests.urls.count == 2)
    }

    @Test("The native page list preserves CDN file order and rejects unsafe response paths")
    func orderedSecurePageURLs() async throws {
        let valid = Data(#"{"result":"ok","baseUrl":"https://uploads.mangadex.org","chapter":{"hash":"abc123","data":["01.jpg","02.png"]}}"#.utf8)
        let runner = HonbakoMangaDexRunner(requestInterval: .zero) { request in
            (valid, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let pages = try await runner.getPageList(manga: manga(), chapter: .init(key: chapterID))
        let urls = pages.compactMap { page -> String? in
            guard case let .url(url, _) = page.content else { return nil }
            return url.absoluteString
        }
        #expect(urls == ["https://uploads.mangadex.org/data/abc123/01.jpg", "https://uploads.mangadex.org/data/abc123/02.png"])
        let malformed = Data(#"{"result":"ok","baseUrl":"https://uploads.mangadex.org","chapter":{"hash":"abc123","data":["../elsewhere.jpg"]}}"#.utf8)
        let unsafe = HonbakoMangaDexRunner(requestInterval: .zero) { request in
            (malformed, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        do {
            _ = try await unsafe.getPageList(manga: manga(), chapter: .init(key: chapterID))
            Issue.record("A page path must not escape the chapter directory")
        } catch {
            #expect(error is HonbakoMangaDexError)
        }
    }

    @Test("Remote native descriptors cannot select arbitrary code or impersonate other source IDs")
    func allowlistedNativeDescriptorAndPersistence() throws {
        func info(id: String, runner: String, version: Int = 1) throws -> ExternalSourceInfo {
            let data = try JSONSerialization.data(withJSONObject: ["id": id, "name": "Catalog Label", "version": version,
                "nativeRunner": runner, "downloadURL": "https://example.test/not-executed.aix"])
            return try JSONDecoder().decode(ExternalSourceInfo.self, from: data)
        }
        #expect(try info(id: "honbako.mangadex", runner: "honbako.mangadex.rest.v1").isNativeInstallable)
        #expect(try !info(id: "local", runner: "honbako.mangadex.rest.v1").isNativeInstallable)
        #expect(try !info(id: "honbako.mangadex", runner: "arbitrary.class").isNativeInstallable)
        #expect(try !info(id: "honbako.mangadex", runner: "honbako.mangadex.rest.v1", version: 2).isNativeInstallable)
        let config = CustomSourceConfig.honbakoMangaDex
        #expect(config.encode() == Data([5]))
        #expect(try CustomSourceConfig(from: config.encode()).toSource().key == "honbako.mangadex")
        #expect(try CustomSourceConfig(from: Data([2])).toSource().key == "local")
    }

    private func manga() -> AidokuRunner.Manga {
        .init(sourceKey: HonbakoMangaDexRunner.sourceKey, key: mangaID, title: "Fixture")
    }

    private func titleData(collection: Bool, longStrip: Bool = false, languages: [Any]? = nil) throws -> Data {
        var attributes: [String: Any] = ["title": ["en": "Fixture"], "year": 1998, "status": "completed",
            "contentRating": "safe", "availableTranslatedLanguages": languages ?? ["en", "es-la", NSNull(), "zh"]]
        if longStrip { attributes["tags"] = [["attributes": ["name": ["en": "Long Strip"]]]] }
        let title: [String: Any] = ["id": mangaID, "type": "manga",
            "attributes": attributes,
            "relationships": [["id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "type": "author", "attributes": ["name": "Fixture Author"]]]]
        let object: [String: Any] = collection
            ? ["result": "ok", "data": [title], "limit": 20, "offset": 0, "total": 1]
            : ["result": "ok", "data": title]
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func chapter(id: String? = nil, language: String = "en", pages: Int = 12,
                         external: String? = nil, publishAt: String = "2020-01-01T00:00:00Z") -> [String: Any] {
        ["id": id ?? chapterID, "type": "chapter", "attributes": [
            "title": "Fixture Chapter", "chapter": "2", "volume": "1", "pages": pages,
            "translatedLanguage": language, "externalUrl": external as Any? ?? NSNull(),
            "publishAt": publishAt, "readableAt": publishAt], "relationships": []]
    }

    private func collection(_ chapters: [[String: Any]], total: Int, offset: Int) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["result": "ok", "data": chapters,
            "limit": chapters.count, "offset": offset, "total": total])
    }

    private actor RequestRecorder {
        private(set) var urls: [URL] = []
        func record(_ request: URLRequest) { if let url = request.url { urls.append(url) } }
    }
}
