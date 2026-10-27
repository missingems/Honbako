@testable import Sumi
import AidokuRunner
import Foundation
import Testing

@MainActor
struct HonbakoTutorialMangaTests {
    @Test("Bundled tutorial has one real three-page edition in each supported language")
    func editionsHaveDistinctReadablePages() throws {
        let manga = try HonbakoTutorialManga.makeManga()
        #expect(manga.identifier == MangaIdentifier(sourceKey: "honbako.tutorial", mangaKey: "first-chapter"))
        let chapters = try #require(manga.chapters)
        #expect(Set(chapters.compactMap(\.language)) == Set(HonbakoTutorialManga.languages))
        for chapter in chapters {
            let pages = try HonbakoTutorialManga.pages(for: chapter)
            #expect(pages.count == 3)
            let urls = pages.compactMap { page -> URL? in
                if case .url(let url, _) = page.content { return url }
                return nil
            }
            #expect(Set(urls).count == 3)
            for url in urls { #expect(FileManager.default.fileExists(atPath: url.path)) }
        }
    }

    @Test("Unsupported or forged tutorial chapters cannot expose unrelated files")
    func unknownChapterRejected() {
        #expect(throws: (any Error).self) {
            try HonbakoTutorialManga.pages(for: AidokuRunner.Chapter(key: "../other-file"))
        }
    }

    @Test("Tutorial language picks Japanese and both Chinese scripts without conflating them")
    func languageSelection() {
        #expect(HonbakoTutorialManga.language(for: "ja-JP") == "ja")
        #expect(HonbakoTutorialManga.language(for: "zh-CN") == "zh-Hans")
        #expect(HonbakoTutorialManga.language(for: "zh-Hant-TW") == "zh-Hant")
        #expect(HonbakoTutorialManga.language(for: "zh-HK") == "zh-Hant")
        #expect(HonbakoTutorialManga.language(for: "fr-FR") == "en")
    }
}
