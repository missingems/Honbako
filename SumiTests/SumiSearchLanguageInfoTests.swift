@testable import Sumi
import Testing

struct SumiSearchLanguageInfoTests {
    @Test("Confirmed chapter languages do not inherit a provider's broader coverage")
    func chapterEvidenceWins() {
        let info = SumiSearchLanguageInfo(chapterLanguages: ["en"], sourceLanguages: ["en", "ja", "es"])
        #expect(info?.scope == .chapters)
        #expect(info?.codes == ["en"])
        #expect(info?.label == "Chapters")
    }

    @Test("Exact-title translations combine with cached chapters without losing script or region")
    func exactTitleTranslations() {
        let info = SumiSearchLanguageInfo(chapterLanguages: [" EN ", "pt_BR"],
            translatedLanguages: ["en", "pt-br", "pt", "zh-Hant"], sourceLanguages: ["multi"])
        #expect(info?.scope == .chapters)
        #expect(Set(info?.codes ?? []) == ["en", "pt-br", "pt", "zh-hant"])
        let aliases = SumiSearchLanguageInfo(chapterLanguages: ["es-la", "es-419", "es"], sourceLanguages: [])
        #expect(Set(aliases?.codes ?? []) == ["es-419", "es"])
    }

    @Test("Provider-only metadata remains qualified and never claims title translations")
    func providerCoverageIsQualified() {
        let specific = SumiSearchLanguageInfo(chapterLanguages: [], sourceLanguages: ["en", "es"])
        #expect(specific?.scope == .source)
        #expect(specific?.label == "Source Languages")
        #expect(specific?.accessibilityText.contains("have not been confirmed") == true)
        let multiple = SumiSearchLanguageInfo(chapterLanguages: [], sourceLanguages: ["multi"])
        #expect(multiple?.scope == .source)
        #expect(multiple?.codes == ["multi"])
        #expect(SumiSearchLanguageInfo(chapterLanguages: [], sourceLanguages: []) == nil)
    }

    @Test("Missing and invalid language markers cannot become confirmed chapter languages")
    func unknownIsNotAConfirmedLanguage() {
        let info = SumiSearchLanguageInfo(chapterLanguages: ["", "multi", "und", "unknown", "<en>"],
            translatedLanguages: ["zxx"], sourceLanguages: ["en"])
        #expect(info?.scope == .source)
        #expect(info?.codes == ["en"])
    }

    @Test("Many translations retain their full list while the row uses two names and a remaining count")
    func longLanguageListIsCompact() {
        let info = SumiSearchLanguageInfo(chapterLanguages: ["en", "ja", "es", "fr", "pt", "de"], sourceLanguages: [])
        #expect(info?.codes.count == 6)
        #expect(info?.compactText.hasSuffix(" +4") == true)
        #expect(info?.text.contains("+4") == false)
        #expect(info?.accessibilityText == info?.text)
    }
}
