@testable import Sumi
import AidokuRunner
import Foundation
import UIKit
import XCTest

@MainActor
final class HonbakoOriginalExternalSourceTests: XCTestCase {
    func testAIXImportSearchAndRead() async throws {
        let source = try await installFixture()
        XCTAssertEqual(source.key, "en.honbako-originals")
        XCTAssertEqual(source.name, "Honbako Originals")
        let search = try await source.getSearchMangaList(query: "BOOKSHOP", page: 1, filters: [])
        XCTAssertEqual(search.entries.count, 1)
        XCTAssertFalse(search.hasNextPage)
        let book = try XCTUnwrap(search.entries.first)
        XCTAssertEqual(book.sourceKey, source.key)
        XCTAssertEqual(book.key, "bookshop-online")
        XCTAssertEqual(book.authors, ["Honbako"])
        XCTAssertEqual(book.status, .completed)
        XCTAssertEqual(book.contentRating, .safe)
        let updated = try await source.getMangaUpdate(manga: book, needsDetails: true, needsChapters: true)
        let chapter = try XCTUnwrap(updated.chapters?.first)
        XCTAssertEqual(updated.chapters?.count, 1)
        XCTAssertEqual(chapter.key, "first-chapter")
        XCTAssertEqual(chapter.chapterNumber, 1)
        XCTAssertEqual(chapter.language, "en")
        let pages = try await source.getPageList(manga: updated, chapter: chapter)
        XCTAssertEqual(pages.count, 6)
        var paths: [String] = []
        for (index, page) in pages.enumerated() {
            guard case .url(let url, _) = page.content else { return XCTFail("Expected an online image page") }
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "missingems.github.io")
            XCTAssertEqual(url.path, "/Honbako/originals/bookshop/page-\(index + 1).png")
            XCTAssertEqual(page.thumbnail, url)
            XCTAssertFalse((page.description ?? "").isEmpty)
            paths.append(url.path)
        }
        XCTAssertEqual(Set(paths).count, 6)
        let listing = try await source.getMangaList(listing: .init(id: "originals", name: "Original Story"), page: 1)
        XCTAssertEqual(listing.entries.map(\.key), [book.key])
        let next = try await source.getSearchMangaList(query: "bookshop", page: 2, filters: [])
        let missing = try await source.getSearchMangaList(query: "not-in-this-catalog", page: 1, filters: [])
        XCTAssertTrue(next.entries.isEmpty)
        XCTAssertTrue(missing.entries.isEmpty)
        await SourceManager.shared.reloadSources()
        let restored = await SourceManager.shared.source(for: source.key)
        XCTAssertNotNil(restored, "Installed .aix source must survive persisted-source loading")
        for _ in 0..<20 {
            let repeated = try await source.getSearchMangaList(query: "pages", page: 1, filters: [])
            XCTAssertEqual(repeated.entries.count, 1, "Immutable result buffers must support repeated native decoding/freeing")
        }
    }

    func testExportOriginalComicAssets() throws {
        let manga = try HonbakoTutorialManga.makeManga()
        XCTAssertEqual(manga.title, "The Bookshop Between Pages")
        let cover = try XCTUnwrap(manga.cover.flatMap(URL.init(string:)))
        let pages = try HonbakoTutorialManga.pages(for: .init(key: "en-first-chapter"))
        XCTAssertEqual(pages.count, 6)
        var files: [(String, URL)] = [("honbako-originals-cover.png", cover)]
        for (index, page) in pages.enumerated() {
            guard case .url(let url, _) = page.content else { return XCTFail("Expected the app's original rendered PNG") }
            files.append(("honbako-originals-page-\(index + 1).png", url))
        }
        var hashes: Set<Data> = []
        for (name, url) in files {
            let data = try Data(contentsOf: url)
            let image = try XCTUnwrap(UIImage(data: data))
            XCTAssertEqual(image.size.width, 1024)
            XCTAssertEqual(image.size.height, 1536)
            hashes.insert(data)
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertEqual(hashes.count, 7, "The cover and six original comic pages must be distinct")
    }

    func testUnknownIdentifiersAndOversizedQueriesFailSafely() async throws {
        let source = try await installFixture()
        let wrong = AidokuRunner.Manga(sourceKey: source.key, key: "other-book", title: "Unknown")
        do { _ = try await source.getMangaUpdate(manga: wrong, needsDetails: true, needsChapters: true); XCTFail("Unknown manga key accepted") } catch {}
        let known = AidokuRunner.Manga(sourceKey: source.key, key: "bookshop-online", title: "Known")
        do { _ = try await source.getPageList(manga: known, chapter: .init(key: "other-chapter")); XCTFail("Unknown chapter accepted") } catch {}
        do { _ = try await source.getSearchMangaList(query: String(repeating: "x", count: 8193), page: 1, filters: []); XCTFail("Oversized query accepted") } catch {}
    }

    private func installFixture() async throws -> AidokuRunner.Source {
        guard HonbakoSourceScope.externalSourcesEnabled else { throw XCTSkip("Use the external beta configuration") }
        let bundle = Bundle(for: Self.self)
        let package = try XCTUnwrap(bundle.url(forResource: "en.honbako-originals", withExtension: "aix"))
        let key = "en.honbako-originals"
        addTeardownBlock { await SourceManager.shared.remove(sourceKey: key) }
        let installed = await SourceManager.shared.importSource(from: package)
        return try XCTUnwrap(installed)
    }
}
