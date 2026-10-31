#if HONBAKO_EXTERNAL_SOURCES
@testable import Sumi
import AidokuRunner
import Testing

@MainActor
struct SumiAlternativeEditionOpeningTests {
    private func chapter(_ key: String, _ number: Float, _ language: String, locked: Bool = false) -> AidokuRunner.Chapter {
        .init(key: key, chapterNumber: number, volumeNumber: 1, language: language, locked: locked)
    }

    @Test("Default English external-only chapters recover into the earliest readable edition without losing unavailable rows")
    func externalOnlyDefault() async throws {
        let original = [chapter("en-2", 2, "en", locked: true), chapter("en-1", 1, "en", locked: true)]
        let alternatives = [chapter("hu-63", 63, "hu"), chapter("az-2", 2, "az"), chapter("az-1", 1, "az")]
        #expect(SumiAlternativeEditionOpening.mayRecover(explicitLanguage: nil, metadataFailed: false, candidateStates: []))
        let plan = try #require(SumiAlternativeEditionOpening.plan(original: original, alternativesNewestFirst: alternatives,
            history: nil, explicitLanguage: nil, configuredLanguages: ["en"], deviceLanguages: ["en-US"]))
        var probes: [String] = []
        let choice = try #require(try await SumiReadableOpeningResolver.resolve(plan.choices, state: { _ in .unknown }) { candidate in
            probes.append(candidate.chapterKey)
            return candidate.chapterKey == "az-1"
        })
        #expect(choice == .init(chapterKey: "az-1", startPage: 1, isFirstRead: true))
        #expect(probes == ["az-1"])
        let actual = try #require(plan.readableChapters.first { $0.key == choice.chapterKey })
        #expect(actual.language == "az")
        let merged = SumiChapterLanguage.merge(original, with: SumiChapterLanguage.filter(plan.readableChapters, language: actual.language))
        #expect(merged.map(\.key) == ["az-2", "az-1", "en-2", "en-1"])
        let englishStillUnavailable = merged.filter { $0.language == "en" }.allSatisfy { $0.locked }
        #expect(englishStillUnavailable)
    }

    @Test("Configured or device languages take precedence over the oldest alternative and regional device codes normalize")
    func preferredAvailableEdition() throws {
        let alternatives = [chapter("hu-63", 63, "hu"), chapter("az-1", 1, "az")]
        for preferences in [(["hu"], ["en"]), (["en"], ["hu-HU"])] {
            let plan = try #require(SumiAlternativeEditionOpening.plan(original: [], alternativesNewestFirst: alternatives,
                history: nil, explicitLanguage: nil, configuredLanguages: preferences.0, deviceLanguages: preferences.1))
            #expect(plan.choices.first?.chapterKey == "hu-63")
        }
    }

    @Test("A manual edition, metadata error or unprobed candidate prevents automatic language changes")
    func recoveryGate() {
        #expect(!SumiAlternativeEditionOpening.mayRecover(explicitLanguage: "en", metadataFailed: false, candidateStates: [.unavailable]))
        #expect(!SumiAlternativeEditionOpening.mayRecover(explicitLanguage: nil, metadataFailed: true, candidateStates: []))
        #expect(!SumiAlternativeEditionOpening.mayRecover(explicitLanguage: nil, metadataFailed: false, candidateStates: [.unavailable, .unknown]))
        #expect(!SumiAlternativeEditionOpening.mayRecover(explicitLanguage: nil, metadataFailed: false, candidateStates: [.available]))
        #expect(SumiAlternativeEditionOpening.plan(original: [], alternativesNewestFirst: [chapter("az-1", 1, "az")],
            history: nil, explicitLanguage: "en", configuredLanguages: [], deviceLanguages: []) == nil)
    }

    @Test("Equivalent translated chapters start at page one without copying or modifying the saved chapter bookmark")
    func translatedResume() throws {
        let original = [chapter("en-2", 2, "en", locked: true), chapter("en-1", 1, "en", locked: true)]
        let alternatives = [chapter("az-2", 2, "az"), chapter("az-1", 1, "az")]
        let history = SumiReaderHistorySnapshot(chapterKey: "en-2", page: 19, completed: false)
        let plan = try #require(SumiAlternativeEditionOpening.plan(original: original, alternativesNewestFirst: alternatives,
            history: history, explicitLanguage: nil, configuredLanguages: ["en"], deviceLanguages: []))
        #expect(plan.choices.first == .init(chapterKey: "az-2", startPage: 1, isFirstRead: false))
        #expect(history == .init(chapterKey: "en-2", page: 19, completed: false))
        let sameEdition = try #require(SumiAlternativeEditionOpening.plan(original: alternatives, alternativesNewestFirst: alternatives,
            history: .init(chapterKey: "az-2", page: 9, completed: false), explicitLanguage: nil,
            configuredLanguages: [], deviceLanguages: []))
        #expect(sameEdition.choices.first?.startPage == 9)
    }

    @Test("A confirmed missing preferred edition advances to another real edition, while network errors remain retryable")
    func missingPreferredAndNetwork() async throws {
        let plan = try #require(SumiAlternativeEditionOpening.plan(original: [],
            alternativesNewestFirst: [chapter("hu-63", 63, "hu"), chapter("az-1", 1, "az"), chapter("locked", 0, "ja", locked: true)],
            history: nil, explicitLanguage: nil, configuredLanguages: ["hu"], deviceLanguages: []))
        #expect(plan.readableChapters.count == 2)
        var probes: [String] = []
        let resolved = try await SumiReadableOpeningResolver.resolve(plan.choices, state: { _ in .unknown }) { candidate in
            probes.append(candidate.chapterKey)
            if candidate.chapterKey == "hu-63" { throw HonbakoMangaDexError.requestFailed(404) }
            return true
        }
        #expect(resolved?.chapterKey == "az-1")
        #expect(probes == ["hu-63", "az-1"])
        probes = []
        do {
            _ = try await SumiReadableOpeningResolver.resolve(plan.choices, state: { _ in .unknown }) { candidate in
                probes.append(candidate.chapterKey)
                throw HonbakoMangaDexError.requestFailed(429)
            }
            Issue.record("A rate limit must stay retryable rather than silently changing editions")
        } catch { #expect(probes == ["hu-63"]) }
    }
}
#endif
