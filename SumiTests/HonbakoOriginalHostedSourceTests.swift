@testable import Sumi
import AidokuRunner
import CryptoKit
import Foundation
import UIKit
import XCTest

@MainActor
final class HonbakoOriginalHostedSourceTests: XCTestCase {
    func testHostedListInstallsAndServesOnlyOriginalContent() async throws {
        guard HonbakoSourceScope.externalSourcesEnabled else { throw XCTSkip("Use the external beta configuration") }
        let manager = SourceManager.shared
        let listURL = try XCTUnwrap(URL(string: "https://missingems.github.io/Honbako/sources/index.json"))
        let key = "en.honbako-originals"
        let previousURLs = await manager.getSourceListURLs()
        let previousSource = await manager.source(for: key)
        guard previousSource == nil, !previousURLs.contains(listURL) else {
            throw XCTSkip("The isolated test must not modify a pre-existing source")
        }
        addTeardownBlock {
            await manager.remove(sourceKey: key)
            await manager.removeSourceList(url: listURL)
        }
        let added = await manager.addSourceList(url: listURL)
        XCTAssertTrue(added, "Live source list must decode and load")
        let lists = await manager.getLoadedSourceLists()
        let list = try XCTUnwrap(lists[listURL])
        XCTAssertEqual(list.name, "Honbako Original Sources")
        XCTAssertEqual(list.sources.count, 1)
        let info = try XCTUnwrap(list.sources.first)
        XCTAssertEqual(info.id, key)
        XCTAssertEqual(info.version, 1)
        XCTAssertEqual(info.resolvedContentRating, .safe)
        let notInstalled = await manager.source(for: key)
        XCTAssertNil(notInstalled, "Adding the list must not auto-install a source")
        let packageURL = try XCTUnwrap(info.fileURL?.absoluteURL)
        let packageData = try await fetchOwned(packageURL)
        XCTAssertEqual(hash(packageData), "441aaa915ad9af95d86e9ebed99328d04c75e1793c37bc8b47594457c3517bec")
        let installation = await manager.installExternalSources(keys: [key])
        let (stream, count) = try XCTUnwrap(installation)
        XCTAssertEqual(count, 1)
        var installed: [String] = []
        for await identifier in stream { installed.append(identifier) }
        XCTAssertEqual(installed, [key])
        let loaded = await manager.source(for: key)
        let source = try XCTUnwrap(loaded)
        let search = try await source.getSearchMangaList(query: "Bookshop", page: 1, filters: [])
        let manga = try XCTUnwrap(search.entries.first)
        XCTAssertEqual(search.entries.count, 1)
        XCTAssertEqual(manga.title, "The Bookshop Between Pages — Online Edition")
        let updated = try await source.getMangaUpdate(manga: manga, needsDetails: true, needsChapters: true)
        let chapter = try XCTUnwrap(updated.chapters?.first)
        let pages = try await source.getPageList(manga: updated, chapter: chapter)
        XCTAssertEqual(pages.count, 6)
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "HonbakoOriginalAssets", withExtension: "json"))
        let manifest = try JSONDecoder().decode(AssetManifest.self, from: Data(contentsOf: fixture))
        let cover = try XCTUnwrap(updated.cover.flatMap(URL.init(string:)))
        var images: [(String, URL)] = [("cover.png", cover)]
        for (index, page) in pages.enumerated() {
            guard case .url(let url, _) = page.content else { return XCTFail("Expected hosted original image") }
            images.append(("page-\(index + 1).png", url))
        }
        for (name, url) in images {
            XCTAssertEqual(url.path, "/Honbako/originals/bookshop/\(name)")
            let expected = try XCTUnwrap(manifest.assets[name])
            let data = try await fetchOwned(url)
            XCTAssertEqual(data.count, expected.bytes, name)
            XCTAssertEqual(hash(data), expected.sha256, name)
            let image = try XCTUnwrap(UIImage(data: data), name)
            XCTAssertEqual(image.size.width, 1024, name)
            XCTAssertEqual(image.size.height, 1536, name)
        }
        await manager.reloadSources()
        let restored = await manager.source(for: key)
        XCTAssertNotNil(restored, "Live installed source must reload")
    }

    private func fetchOwned(_ url: URL) async throws -> Data {
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "missingems.github.io")
        XCTAssertTrue(url.path.hasPrefix("/Honbako/"))
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, url.absoluteString)
        XCTAssertEqual(response.url?.host, "missingems.github.io")
        return data
    }

    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct AssetManifest: Decodable {
        struct Asset: Decodable { let sha256: String; let bytes: Int }
        let assets: [String: Asset]
    }
}
