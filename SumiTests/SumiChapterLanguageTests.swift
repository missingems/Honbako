@testable import Sumi
import AidokuRunner
import Foundation
import Testing

struct SumiChapterLanguageTests {
    @Test("Resuming the exact chapter wins over another device's language preference")
    func resumedLanguage() {
        let english = chapter("en", language: "en")
        let japanese = chapter("ja", language: "ja")
        #expect(SumiChapterLanguage.activeLanguage(chapters: [english, japanese], currentChapter: japanese, preferred: "en") == "ja")
        #expect(SumiChapterLanguage.activeLanguage(chapters: [english], currentChapter: chapter("unknown", language: nil), preferred: "en") == nil)
    }

    @Test("Routes never mix languages or silently combine regional translations")
    func exactRoutes() {
        let chapters = [chapter("br", language: "pt-BR"), chapter("pt", language: "pt"),
                        chapter("en", language: "en"), chapter("unknown", language: nil)]
        #expect(SumiChapterLanguage.filter(chapters, language: "PT_br").map(\.key) == ["br"])
        #expect(SumiChapterLanguage.filter(chapters, language: "en").map(\.key) == ["en"])
        #expect(SumiChapterLanguage.filter(chapters, language: "ja").isEmpty)
        #expect(SumiChapterLanguage.filter(chapters, language: nil).count == chapters.count)
    }

    @Test("Fetched translations preserve the other language and update matching keys")
    func mergedChapters() {
        let old = [chapter("en2", number: 2, language: "en"), chapter("en1", number: 1, language: "en")]
        var updated = old[0]
        updated.title = "Updated"
        let merged = SumiChapterLanguage.merge(old, with: [chapter("ja2", number: 2, language: "ja"), updated])
        #expect(Set(merged.map(\.key)) == ["en2", "en1", "ja2"])
        #expect(merged.first(where: { $0.key == "en2" })?.title == "Updated")
        #expect(merged.last?.chapterNumber == 1)
    }

    @Test("Source-order chapters remain ordered when a chapter has no number")
    func sourceOrderMerge() {
        let entries = [chapter("first", number: 1, language: "en"), chapter("extra", language: "en"),
                       chapter("second", number: 2, language: "en")]
        #expect(SumiChapterLanguage.merge([], with: entries).map(\.key) == entries.map(\.key))
    }

    @Test("A language change continues the same numbered chapter and volume, preserving the source's edition order")
    func translatedChapterMatch() {
        let current = AidokuRunner.Chapter(key: "english", chapterNumber: 2, volumeNumber: 3, language: "en")
        let chapters: [AidokuRunner.Chapter] = [
            .init(key: "wrong-volume", chapterNumber: 2, volumeNumber: 2, language: "fr"),
            .init(key: "fr-first-edition", chapterNumber: 2, volumeNumber: 3, language: "fr"),
            .init(key: "fr-second-edition", chapterNumber: 2, volumeNumber: 3, language: "fr"),
            .init(key: "wrong-language", chapterNumber: 2, volumeNumber: 3, language: "pt")
        ]
        #expect(SumiChapterLanguage.equivalent(to: current, in: chapters, language: "fr")?.key == "fr-first-edition")
        #expect(SumiChapterLanguage.equivalent(to: current, in: chapters, language: "pt-BR") == nil)
    }

    @Test("Missing volume metadata can match an unambiguous translation but cannot cross an explicit volume reset")
    func translatedVolumeAmbiguity() {
        let numberedVolume = AidokuRunner.Chapter(key: "current-v2", chapterNumber: 1, volumeNumber: 2, language: "en")
        let missingVolume = AidokuRunner.Chapter(key: "fr-no-volume", chapterNumber: 1, language: "fr")
        #expect(SumiChapterLanguage.equivalent(to: numberedVolume, in: [missingVolume], language: "fr")?.key == missingVolume.key)
        let otherVolume = AidokuRunner.Chapter(key: "fr-v1", chapterNumber: 1, volumeNumber: 1, language: "fr")
        #expect(SumiChapterLanguage.equivalent(to: numberedVolume, in: [otherVolume, missingVolume], language: "fr") == nil)
        let noVolume = AidokuRunner.Chapter(key: "current-no-volume", chapterNumber: 1, language: "en")
        let secondVolume = AidokuRunner.Chapter(key: "fr-v2", chapterNumber: 1, volumeNumber: 2, language: "fr")
        #expect(SumiChapterLanguage.equivalent(to: noVolume, in: [otherVolume, secondVolume], language: "fr") == nil)
    }

    @Test("An unnumbered special needs a matching title, never just the same list position")
    func translatedSpecials() {
        let special = AidokuRunner.Chapter(key: "extra-en", title: "Bonus  Chapter", language: "en")
        let matching = AidokuRunner.Chapter(key: "extra-fr", title: "  BONUS Chapter ", language: "fr")
        let different = AidokuRunner.Chapter(key: "different-fr", title: "Afterword", language: "fr")
        #expect(SumiChapterLanguage.equivalent(to: special, in: [different, matching], language: "fr")?.key == matching.key)
        #expect(SumiChapterLanguage.equivalent(to: special, in: [different], language: "fr") == nil)
        #expect(SumiChapterLanguage.equivalent(to: chapter("unknown", language: "en"), in: [matching], language: "fr") == nil)
    }

    @Test("Language switches prefer the translation's own bookmark and otherwise keep the current page")
    func translatedPageProgress() {
        #expect(SumiChapterLanguage.resumePage(savedPage: 7, currentPage: 19) == 7)
        #expect(SumiChapterLanguage.resumePage(savedPage: nil, currentPage: 19) == 19)
        #expect(SumiChapterLanguage.resumePage(savedPage: 0, currentPage: 19) == 19)
        #expect(SumiChapterLanguage.resumePage(savedPage: nil, currentPage: -1) == 1)
    }

    @Test("Reviewed source language settings describe isolated fetch capabilities, not title choices")
    func scopedTranslationDiscovery() {
        let languages = ["en", "ja", "PT_br", "pt-BR"]
        for source in ["multi.mangadex", "multi.mangafire"] {
            #expect(Set(SumiLanguageChapterLoader.translationLanguages(sourceKey: source,
                advertisedLanguages: languages, hasPackage: true)) == ["en", "ja", "pt-br"])
        }
        for source in ["multi.mangaplus", "multi.webtoon", "unreviewed-source"] {
            #expect(SumiLanguageChapterLoader.translationLanguages(sourceKey: source,
                advertisedLanguages: languages, hasPackage: true).isEmpty)
        }
        #expect(SumiLanguageChapterLoader.translationLanguages(sourceKey: "multi.mangadex",
            advertisedLanguages: languages, hasPackage: false).isEmpty)
        #expect(SumiLanguageChapterLoader.translationLanguages(sourceKey: "multi.mangadex",
            advertisedLanguages: ["en", "EN"], hasPackage: true).isEmpty)
    }

    @Test("Native reader choices use this title's translations and cached chapter labels, never global source coverage")
    func nativeTitleLanguageChoices() {
        let cached = [chapter("english", language: "en"), chapter("saved-japanese", language: "ja")]
        let sourceLanguages = ["en", "fr", "pt-BR", "es", "ja"]
        let beforeDiscovery = SumiLanguageChapterLoader.offeredLanguages(chapters: cached,
            sourceKey: "honbako.mangadex", advertisedLanguages: sourceLanguages, hasPackage: false)
        #expect(Set(beforeDiscovery) == ["en", "ja"])
        let discovered = SumiLanguageChapterLoader.offeredLanguages(chapters: cached,
            sourceKey: "honbako.mangadex", advertisedLanguages: sourceLanguages, hasPackage: false,
            nativeTitleLanguages: ["en", "km", "pt_BR", "pt", "es-la"])
        #expect(Set(discovered) == ["en", "ja", "km", "pt-br", "pt", "es-419"])
        #expect(!discovered.contains("fr"))
        #expect(SumiLanguageChapterLoader.translationLanguages(sourceKey: "honbako.mangadex",
            advertisedLanguages: sourceLanguages, hasPackage: false).isEmpty)
    }

    @Test("Legacy reader choices never promote source-wide languages into this title's menu")
    func legacyTitleLanguageChoices() {
        let cached = [chapter("english", language: "en"), chapter("portuguese", language: "pt-BR")]
        for source in ["multi.mangadex", "multi.mangafire", "multi.webtoon"] {
            let offered = SumiLanguageChapterLoader.offeredLanguages(chapters: cached,
                sourceKey: source, advertisedLanguages: ["en", "ja", "fr", "pt-BR"], hasPackage: true,
                nativeTitleLanguages: ["es"])
            #expect(Set(offered) == ["en", "pt-br"])
            #expect(!offered.contains("ja") && !offered.contains("fr") && !offered.contains("es"))
        }
    }

    @Test("A saved native language outside the catalog list is fetched when reopening the title")
    func nativePreferredLanguageOutsideCatalog() async throws {
        let suite = "Sumi.NativePreferredLanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["en"], forKey: HonbakoMangaDexRunner.sourceKey + ".languages")
        let mangaKey = "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb"
        let native = HonbakoMangaDexRunner(defaults: defaults, requestInterval: .zero) { request in
            let url = request.url!
            let json: [String: Any]
            if url.path.hasSuffix("/feed") {
                let language = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .first { $0.name == "translatedLanguage[]" }?.value ?? "en"
                json = ["result": "ok", "limit": 500, "offset": 0, "total": 1,
                    "data": [["id": language == "km" ? "bbbbbbbb-1111-2222-3333-cccccccccccc" : "cccccccc-1111-2222-3333-dddddddddddd",
                              "attributes": ["chapter": "2", "pages": 1, "translatedLanguage": language]]]]
            } else {
                json = ["result": "ok", "data": ["id": mangaKey,
                    "attributes": ["title": ["en": "Title"], "availableTranslatedLanguages": ["en", "km"]]]]
            }
            return (try JSONSerialization.data(withJSONObject: json),
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let source = AidokuRunner.Source(key: HonbakoMangaDexRunner.sourceKey, name: "MangaDex", version: 1,
            languages: ["en"], contentRating: .safe, runner: native)
        let manga = AidokuRunner.Manga(sourceKey: source.key, key: mangaKey, title: "Title")
        let refreshed = try await SumiLanguageChapterLoader.update(source: source, manga: manga,
            needsDetails: false, preferredLanguage: "km")
        #expect(Set((refreshed.chapters ?? []).compactMap(\.language)) == ["en", "km"])
        #expect(defaults.stringArray(forKey: HonbakoMangaDexRunner.sourceKey + ".languages") == ["en"])
    }

    @Test("MangaFire's returned es-la chapters match requested es-419 without mixing other regional editions")
    func mangaFireRegionalAlias() throws {
        let advertised = ["en", "es", "es-419", "pt", "pt-BR"]
        let providerValue = try #require(SumiLanguageChapterLoader.providerLanguage(for: "es-419", advertisedLanguages: advertised))
        #expect(providerValue == "es-419")
        #expect(SumiLanguageChapterLoader.providerLanguage(for: "es-la", advertisedLanguages: advertised) == "es-419")
        #expect(SumiLanguageChapterLoader.providerLanguage(for: "es-419", advertisedLanguages: ["es-la", "es"]) == "es-la")
        #expect(Set(SumiLanguageChapterLoader.translationLanguages(sourceKey: "multi.mangafire",
            advertisedLanguages: ["en", "es-la", "es-419", "es", "pt", "pt-BR"], hasPackage: true))
            == ["en", "es-419", "es", "pt", "pt-br"])
        let returned = [chapter("latam", language: "es-la"), chapter("spain", language: "es"),
                        chapter("brazil", language: "pt-br"), chapter("portugal", language: "pt")]
        #expect(SumiChapterLanguage.filter(returned, language: "es-419").map(\.key) == ["latam"])
        #expect(SumiChapterLanguage.filter(returned, language: "es").map(\.key) == ["spain"])
        #expect(SumiChapterLanguage.filter(returned, language: "pt-BR").map(\.key) == ["brazil"])
        #expect(SumiChapterLanguage.filter(returned, language: "pt").map(\.key) == ["portugal"])

        let suite = "Sumi.MangaFireLanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["en"], forKey: "multi.mangafire.languages")
        let scope = SumiLanguagePreferenceScope(sourceKey: "multi.mangafire", language: providerValue, defaults: defaults)
        defer { scope.remove() }
        #expect(defaults.stringArray(forKey: scope.namespace + ".languages") == ["es-419"])
        #expect(defaults.stringArray(forKey: "multi.mangafire.languages") == ["en"])
    }

    @Test("Concurrent language fetch preferences are isolated and cleaned without changing source settings")
    func isolatedPreferences() throws {
        let suite = "Sumi.LanguageScopeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["en"], forKey: "provider.languages")
        defaults.set("https://example.invalid", forKey: "provider.baseURL")
        defaults.set("unrelated", forKey: "anotherProvider.language")
        let japanese = SumiLanguagePreferenceScope(sourceKey: "provider", language: "ja", defaults: defaults)
        let french = SumiLanguagePreferenceScope(sourceKey: "provider", language: "fr", defaults: defaults)
        #expect(defaults.stringArray(forKey: "provider.languages") == ["en"])
        #expect(defaults.stringArray(forKey: japanese.namespace + ".languages") == ["ja"])
        #expect(defaults.stringArray(forKey: french.namespace + ".languages") == ["fr"])
        #expect(defaults.string(forKey: japanese.namespace + ".baseURL") == "https://example.invalid")
        japanese.remove()
        #expect(defaults.object(forKey: japanese.namespace + ".languages") == nil)
        #expect(defaults.stringArray(forKey: french.namespace + ".languages") == ["fr"])
        french.remove()
        #expect(defaults.string(forKey: "anotherProvider.language") == "unrelated")
        #expect(defaults.stringArray(forKey: "provider.languages") == ["en"])
    }

    @Test("Free sync migrates once and preserves later choices")
    func automaticSyncDefault() throws {
        let suite = "Sumi.SyncDefaultsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "General.icloudSync")
        SumiDefaults.register(in: defaults)
        #expect(defaults.bool(forKey: "General.icloudSync"), "The old Pro-only setting is migrated to free sync")
        #expect(defaults.string(forKey: "Reader.readingMode") == "auto")
        defaults.set(false, forKey: "General.icloudSync")
        SumiDefaults.register(in: defaults)
        #expect(!defaults.bool(forKey: "General.icloudSync"), "Later launches preserve the reader's explicit choice")
    }

    private func chapter(_ key: String, number: Float? = nil, language: String?) -> AidokuRunner.Chapter {
        .init(key: key, chapterNumber: number, language: language)
    }
}
