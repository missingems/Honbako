@testable import Sumi
import Foundation
import StoreKit
import Testing

struct HonbakoSubscriptionTrialTests {
    @Test("A free introductory offer requires current eligibility and one valid period")
    func rejectsIneligibleAndPaidOffers() {
        #expect(trial() != nil)
        #expect(trial(eligible: false) == nil)
        #expect(trial(type: .promotional) == nil)
        #expect(trial(type: .winBack) == nil)
        #expect(trial(mode: .payUpFront) == nil)
        #expect(trial(mode: .payAsYouGo) == nil)
        #expect(trial(price: Decimal(string: "0.01")!) == nil)
        #expect(trial(value: 0) == nil)
        #expect(trial(value: -1) == nil)
        #expect(trial(count: 0) == nil)
        #expect(trial(count: 2) == nil)
    }

    @Test("Trial wording preserves Apple's actual duration, including non-default durations")
    func durationMetadata() throws {
        for (unit, value, title) in [
            (Product.SubscriptionPeriod.Unit.day, 3, "3-day free trial"),
            (.week, 1, "1-week free trial"),
            (.week, 2, "2-week free trial"),
            (.month, 1, "1-month free trial"),
            (.year, 1, "1-year free trial")
        ] {
            let offer = try #require(trial(unit: unit, value: value))
            #expect(offer.periodValue == value)
            #expect(offer.periodUnit == unit)
            #expect(offer.title == title)
            #expect(!offer.durationDescription.isEmpty)
            #expect(offer.durationDescription.contains(value.formatted()))
        }
    }

    private func trial(eligible: Bool = true,
                       type: Product.SubscriptionOffer.OfferType = .introductory,
                       mode: Product.SubscriptionOffer.PaymentMode = .freeTrial,
                       price: Decimal = 0, unit: Product.SubscriptionPeriod.Unit = .week,
                       value: Int = 1, count: Int = 1) -> HonbakoSubscriptionTrial? {
        .init(isEligible: eligible, offerType: type, paymentMode: mode, price: price,
              periodUnit: unit, periodValue: value, periodCount: count)
    }
}
