@testable import Sumi
import Foundation
import Testing
import UIKit

@MainActor
@Suite struct HonbakoJapanesePageLoaderTests {
    @Test("Learning loads the original page, not a cropped filmstrip preview")
    func originalImages() async throws {
        let loader = HonbakoJapanesePageLoader()
        let image = HonbakoJapanesePracticePage.render()
        let inline = Page(sourceId: "honbako.tutorial", chapterId: "ja", image: image)
        let result = try #require(await loader.image(for: inline, source: nil))
        #expect(result === image)
        let data = try #require(image.pngData())
        let encoded = Page(sourceId: "honbako.tutorial", chapterId: "ja", base64: data.base64EncodedString())
        let decoded = try #require(await loader.image(for: encoded, source: nil))
        #expect(decoded.size == image.size)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let local = Page(sourceId: "honbako.tutorial", chapterId: "ja", imageURL: file.absoluteString)
        let loaded = try #require(await loader.image(for: local, source: nil))
        #expect(loaded.size == image.size)
    }

    @Test("Chapter boundaries and text-only pages are never sent for image recognition")
    func excludesNonPages() async {
        let loader = HonbakoJapanesePageLoader()
        let image = HonbakoJapanesePracticePage.render()
        let boundary = Page(type: .nextInfoPage, sourceId: "test", chapterId: "next", image: image)
        let text = Page(sourceId: "test", chapterId: "one", text: "text page", image: image)
        #expect(await loader.image(for: boundary, source: nil) == nil)
        #expect(await loader.image(for: text, source: nil) == nil)
        let invalid = Page(sourceId: "test", chapterId: "one", base64: "not base64")
        #expect(await loader.image(for: invalid, source: nil) == nil)
    }
}
