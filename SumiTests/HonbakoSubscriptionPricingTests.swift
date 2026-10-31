@testable import Sumi
import Foundation
import Testing

struct HonbakoSubscriptionPricingTests {
    @Test("Annual savings derive from actual localized prices and always round down")
    func actualSavings() {
        #expect(HonbakoSubscriptionPricing.saving(monthly: Decimal(string: "2.99")!, annual: Decimal(string: "28.49")!) == 20)
        #expect(HonbakoSubscriptionPricing.saving(monthly: Decimal(string: "2.99")!, annual: Decimal(string: "28.99")!) == 19)
        #expect(HonbakoSubscriptionPricing.saving(monthly: 4, annual: 39) == 18)
        #expect(HonbakoSubscriptionPricing.saving(monthly: 0, annual: 20) == nil)
        #expect(HonbakoSubscriptionPricing.saving(monthly: 3, annual: 36) == nil)
        #expect(HonbakoSubscriptionPricing.saving(monthly: 3, annual: 40) == nil)
    }
    @Test("Only the known monthly and annual products can unlock Pro")
    func productAllowlist() {
        #expect(HonbakoProStore.productIDs == ["com.missingems.honbaku.pro", "com.missingems.honbaku.pro.annual"])
    }
}
