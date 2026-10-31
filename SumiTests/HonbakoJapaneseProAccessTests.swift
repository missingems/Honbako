@testable import Sumi
import AidokuRunner
import Foundation
import Testing
import UIKit

@MainActor
struct HonbakoJapaneseProAccessTests {
    @Test("Free access cannot activate live Japanese guidance, even with eligible artwork and a saved request")
    func verifiedAccessRequired() {
        let access = HonbakoJapaneseLearningPolicy(requested: true, languageEligible: true, hasPro: false)
        #expect(!access.enabled)
    }

    @Test("Purchasing Pro never enables annotations for Chinese or an unselected guide")
    func independentUserAndLanguageIntent() {
        let chinese = HonbakoJapaneseLanguageEligibility.allows(chapterLanguage: "zh-Hans", sourceLanguages: ["ja"])
        #expect(!HonbakoJapaneseLearningPolicy(requested: true, languageEligible: chinese, hasPro: true).enabled)
        #expect(!HonbakoJapaneseLearningPolicy(requested: false, languageEligible: true, hasPro: true).enabled)
        #expect(HonbakoJapaneseLearningPolicy(requested: true, languageEligible: true, hasPro: true).enabled)
    }

    @Test("Pro revocation stops requested Japanese overlays and a new reader starts with guidance off")
    func revocationAndFreshReader() {
        let paid = HonbakoJapaneseLearningPolicy(requested: true, languageEligible: true, hasPro: true)
        let revoked = HonbakoJapaneseLearningPolicy(requested: true, languageEligible: true, hasPro: false)
        #expect(paid.enabled && !revoked.enabled)
        let manga = AidokuRunner.Manga(sourceKey: "pro-guide-test", key: "owned", title: "Owned Practice")
        let chapter = AidokuRunner.Chapter(key: "one", language: "ja")
        let reader = ReaderViewController(source: nil, manga: manga, chapter: chapter)
        #expect(!reader.sumiJapaneseLearningEnabled)
        #expect(!reader.sumiJapaneseLearningPolicy.enabled)
        #expect(reader.presentedViewController == nil, "A free reader never presents a paywall automatically")
    }
}
