@testable import Sumi
import AidokuRunner
import Foundation
import Testing

@MainActor
@Suite struct HonbakoJapaneseLanguageEligibilityTests {
    @Test("Japanese chapter tags enable annotations even on a multilingual catalog")
    func japaneseTranslations() {
        for language in ["ja", "ja-JP", "JA_jp", "ja-Jpan-JP", "jpn", "  ja  "] {
            #expect(HonbakoJapaneseLanguageEligibility.allows(chapterLanguage: language,
                sourceLanguages: ["en", "zh-Hans", "ja"]))
        }
    }

    @Test("Chinese and other explicit chapter languages override a Japanese source")
    func explicitTranslationWins() {
        for language in ["zh", "zh-Hans", "zh-Hant", "zh-CN", "zh-TW", "zh-HK", "en", "ko", "fr", "multi", "und", "unknown"] {
            #expect(!HonbakoJapaneseLanguageEligibility.allows(chapterLanguage: language, sourceLanguages: ["ja"]))
        }
    }

    @Test("A chapter without language metadata needs an unambiguously Japanese source")
    func sourceFallbackRequiresCertainty() {
        for language: String? in [nil, "", "  "] {
            #expect(HonbakoJapaneseLanguageEligibility.allows(chapterLanguage: language, sourceLanguages: ["ja"]))
            #expect(HonbakoJapaneseLanguageEligibility.allows(chapterLanguage: language, sourceLanguages: ["ja", "ja-JP"]))
            for source in [[], ["en"], ["zh-Hant"], ["ja", "en"], ["ja", "zh"], ["ja", "multi"], ["ja", ""], ["unknown"]] {
                #expect(!HonbakoJapaneseLanguageEligibility.allows(chapterLanguage: language, sourceLanguages: source))
            }
        }
    }

    @Test("Mixed language strings and malformed Japanese tags are not language evidence")
    func malformedAndCombinedLabelsStayOff() {
        for language in ["ja,zh", "ja en", "ja/zh", "ja-", "ja--JP", "ja_日本語", "Japanese", "日本語"] {
            #expect(!HonbakoJapaneseLanguageEligibility.allows(chapterLanguage: language, sourceLanguages: ["ja"]))
            #expect(!HonbakoJapaneseLanguageEligibility.allows(chapterLanguage: nil, sourceLanguages: [language]))
        }
    }

    @Test("Only the known original Japanese practice page bypasses a localized guide's language")
    func originalPracticePageMetadata() {
        for language in ["en", "ja", "zh-Hans", "zh-Hant"] {
            let chapterKey = language + "-guide-japanese"
            for index in [0, 1, 2, 3] {
                let isPractice = HonbakoJapaneseLanguageEligibility.isOriginalPracticePage(sourceKey: "honbako.tutorial",
                    mangaKey: "guide-japanese", chapterKey: chapterKey, pageIndex: index)
                #expect(isPractice == (index == 1))
                if language != "ja" {
                    #expect(HonbakoJapaneseLanguageEligibility.allowsPage(chapterLanguage: language,
                        sourceLanguages: ["en", "ja", "zh-Hans", "zh-Hant"], sourceKey: "honbako.tutorial",
                        mangaKey: "guide-japanese", chapterKey: chapterKey, pageIndex: index) == (index == 1))
                }
            }
        }
        for (source, manga, chapter) in [
            ("external", "guide-japanese", "en-guide-japanese"),
            ("honbako.tutorial", "guide-find", "en-guide-find"),
            ("honbako.tutorial", "first-chapter", "en-first-chapter"),
            ("honbako.tutorial", "guide-japanese", "unrecognized-chapter")
        ] {
            #expect(!HonbakoJapaneseLanguageEligibility.isOriginalPracticePage(sourceKey: source,
                mangaKey: manga, chapterKey: chapter, pageIndex: 1))
        }
    }

    @Test("Chapter loading overwrites untrusted flags and retains eligibility with the preloaded chapter")
    func loadedAndPreloadedPagesKeepTheirOwnLanguage() async {
        let source = AidokuRunner.Source(key: "language-gate-test", name: "Japanese catalog", version: 1,
            languages: ["ja"], contentRating: .safe, runner: HonbakoTutorialRunner())
        let manga = AidokuRunner.Manga(sourceKey: source.key, key: "book", title: "Test")
        let model = ReaderPagedViewModel(source: source, manga: manga)
        model.sumiPageLoaderOverride = { chapter in
            var page = Sumi.Page(sourceId: manga.sourceKey, chapterId: chapter.key, index: 0, language: "ja")
            page.sumiJapaneseLearningEligible = true
            return [page]
        }
        let chinese = AidokuRunner.Chapter(key: "chinese", language: "zh-Hant")
        let japanese = AidokuRunner.Chapter(key: "japanese", language: "ja-JP")
        #expect(await model.loadPages(chapter: chinese))
        #expect(model.pages.first?.sumiJapaneseLearningEligible == false)
        let prepared = await model.preload(chapter: japanese)
        #expect(prepared.first?.sumiJapaneseLearningEligible == true)
        #expect(model.pages.first?.sumiJapaneseLearningEligible == false,
            "Preparing a Japanese neighbor must not annotate the current Chinese chapter")
        #expect(await model.loadPages(chapter: japanese))
        #expect(model.pages.first?.sumiJapaneseLearningEligible == true)
    }

    @Test("A multilingual source's first advertised language cannot enable an unknown chapter")
    func sourceFirstLanguageIsNotChapterMetadata() async {
        let source = AidokuRunner.Source(key: "language-gate-multi", name: "Multilingual catalog", version: 1,
            languages: ["ja", "zh-Hans"], contentRating: .safe, runner: HonbakoTutorialRunner())
        let manga = AidokuRunner.Manga(sourceKey: source.key, key: "book", title: "Test")
        let model = ReaderPagedViewModel(source: source, manga: manga)
        model.sumiPageLoaderOverride = { chapter in
            [Sumi.Page(sourceId: manga.sourceKey, chapterId: chapter.key, index: 0, language: "ja")]
        }
        #expect(await model.loadPages(chapter: .init(key: "unknown")))
        #expect(model.pages.first?.sumiJapaneseLearningEligible == false)
    }

    @Test("The localized guide annotates its original practice bitmap and none of the surrounding guide pages")
    func localizedGuidePageGate() async {
        let manga = AidokuRunner.Manga(sourceKey: "honbako.tutorial", key: "guide-japanese", title: "Reading Japanese")
        let model = ReaderPagedViewModel(source: nil, manga: manga)
        model.sumiPageLoaderOverride = { chapter in
            (0..<4).map { Sumi.Page(sourceId: manga.sourceKey, chapterId: chapter.key, index: $0, language: "zh-Hans") }
        }
        #expect(await model.loadPages(chapter: .init(key: "zh-Hans-guide-japanese", language: "zh-Hans")))
        #expect(model.pages.map(\.sumiJapaneseLearningEligible) == [false, true, false, false])
    }
}
