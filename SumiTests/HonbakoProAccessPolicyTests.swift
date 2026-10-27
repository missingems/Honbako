@testable import Sumi
import Foundation
import Testing

struct HonbakoProAccessPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let product = "com.missingems.honbaku.pro"

    @Test("Personal access requires the explicit signed-build value and fails closed when missing")
    func personalBuildConfiguration() {
        let key = HonbakoProAccessPolicy.personalFeaturesInfoKey
        #expect(HonbakoProAccessPolicy.personalFeaturesEnabled(infoDictionary: [key: "YES"]))
        let disabledValues: [Any] = ["NO", "", "$(HONBAKO_PERSONAL_FEATURES)", "true", true, 1]
        for value in disabledValues {
            #expect(!HonbakoProAccessPolicy.personalFeaturesEnabled(infoDictionary: [key: value]))
        }
        #expect(!HonbakoProAccessPolicy.personalFeaturesEnabled(infoDictionary: [:]))
        #expect(!HonbakoProAccessPolicy.personalFeaturesEnabled(infoDictionary: nil))
    }

    @Test("Personal features work without creating or relying on an App Store claim")
    func personalAccessWithoutPurchase() {
        #expect(HonbakoProAccessPolicy.hasPro(personalFeaturesEnabled: true,
            verifiedEntitlement: nil, at: now, productID: product))
        let expired = HonbakoProEntitlement(productID: product, expirationDate: now,
            revocationDate: nil, verifiedAt: now)
        #expect(HonbakoProAccessPolicy.hasPro(personalFeaturesEnabled: true,
            verifiedEntitlement: expired, at: now, productID: product))
    }

    @Test("Public builds continue to require the actual verified subscription claim")
    func publicAccessRequiresSubscription() {
        #expect(!HonbakoProAccessPolicy.hasPro(personalFeaturesEnabled: false,
            verifiedEntitlement: nil, at: now, productID: product))
        let active = HonbakoProEntitlement(productID: product, expirationDate: now.addingTimeInterval(60),
            revocationDate: nil, verifiedAt: now)
        #expect(HonbakoProAccessPolicy.hasPro(personalFeaturesEnabled: false,
            verifiedEntitlement: active, at: now, productID: product))
        #expect(!HonbakoProAccessPolicy.hasPro(personalFeaturesEnabled: false,
            verifiedEntitlement: active, at: now.addingTimeInterval(60), productID: product))
    }
}
