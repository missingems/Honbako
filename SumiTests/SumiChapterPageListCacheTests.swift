@testable import Sumi
import AidokuRunner
import Foundation
import Testing

struct SumiChapterPageListCacheTests {
    private actor Loader {
        var count = 0
        let pages: [AidokuRunner.Page]
        init(pages: [AidokuRunner.Page]) { self.pages = pages }
        func load() async throws -> [AidokuRunner.Page] {
            count += 1
            try await Task.sleep(for: .milliseconds(10))
            return pages
        }
    }

    @Test("Reopening shares a live request, while expiry and explicit retry fetch fresh URLs")
    func sharedRequestAndFreshRetry() async throws {
        let marker = NSObject()
        defer { withExtendedLifetime(marker) {} }
        let key = SumiChapterPageListCache.Key(sourceInstance: ObjectIdentifier(marker), sourceKey: "test",
            mangaKey: "book", chapterKey: "chapter", language: "en")
        let cache = SumiChapterPageListCache()
        let pages = [AidokuRunner.Page(content: .url(url: URL(string: "https://example.invalid/1.jpg")!))]
        let loader = Loader(pages: pages)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        async let first = cache.pages(for: key, now: now) { try await loader.load() }
        async let second = cache.pages(for: key, now: now) { try await loader.load() }
        let results = try await [first, second]
        #expect(results == [pages, pages])
        #expect(await loader.count == 1)
        _ = try await cache.pages(for: key, now: now.addingTimeInterval(30)) { try await loader.load() }
        #expect(await loader.count == 1)
        _ = try await cache.pages(for: key, now: now.addingTimeInterval(61)) { try await loader.load() }
        #expect(await loader.count == 2)
        _ = try await cache.pages(for: key, forceRefresh: true, now: now.addingTimeInterval(62)) { try await loader.load() }
        #expect(await loader.count == 3)
    }

    @Test("Local content is never retained by the shared URL response cache")
    func localContentIsNotCached() async throws {
        let marker = NSObject()
        defer { withExtendedLifetime(marker) {} }
        let key = SumiChapterPageListCache.Key(sourceInstance: ObjectIdentifier(marker), sourceKey: "test",
            mangaKey: "book", chapterKey: "chapter", language: "en")
        let cache = SumiChapterPageListCache()
        let loader = Loader(pages: [.init(content: .text("A personal local document"))])
        _ = try await cache.pages(for: key) { try await loader.load() }
        _ = try await cache.pages(for: key) { try await loader.load() }
        #expect(await loader.count == 2)
    }
}
