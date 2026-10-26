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

    @Test("A fresh Honbako store keeps Pro sync disabled without a verified purchase")
    func automaticSyncDefault() throws {
        let suite = "Sumi.SyncDefaultsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "General.icloudSync")
        SumiDefaults.register(in: defaults)
        #expect(!defaults.bool(forKey: "General.icloudSync"))
        #expect(defaults.string(forKey: "Reader.readingMode") == "auto")
    }

    private func chapter(_ key: String, number: Float? = nil, language: String?) -> AidokuRunner.Chapter {
        .init(key: key, chapterNumber: number, language: language)
    }
}
