@testable import Sumi
import Foundation
import Testing

struct HonbakoBuildVariantTests {
    @Test("The signed source capability matches the compiled variant independently of Pro access")
    func signedCapabilityMatchesCompilation() {
        let signed = Bundle.main.object(forInfoDictionaryKey: "HonbakoExternalSources") as? String == "YES"
        #expect(signed == HonbakoSourceScope.externalSourcesEnabled)
        #expect(Bundle.main.object(forInfoDictionaryKey: "HonbakoPersonalFeatures") as? String == "NO")
        #expect(Bundle.main.object(forInfoDictionaryKey: "HonbakoImportEnglish50") as? String == "NO")
        #expect(!HonbakoProStore.personalFeaturesEnabled)
    }
}
