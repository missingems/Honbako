#if SUMI
import Foundation
import StoreKit

/// A trial is shown only when Apple's current offer and group eligibility
/// confirm it. Durations are never inferred from a plan name or SKU.
struct HonbakoSubscriptionTrial: Equatable, Sendable {
    let periodValue: Int
    let periodUnit: Product.SubscriptionPeriod.Unit

    init?(offer: Product.SubscriptionOffer, isEligible: Bool) {
        self.init(isEligible: isEligible, offerType: offer.type,
                  paymentMode: offer.paymentMode, price: offer.price,
                  periodUnit: offer.period.unit, periodValue: offer.period.value,
                  periodCount: offer.periodCount)
    }

    init?(isEligible: Bool, offerType: Product.SubscriptionOffer.OfferType,
          paymentMode: Product.SubscriptionOffer.PaymentMode, price: Decimal,
          periodUnit: Product.SubscriptionPeriod.Unit, periodValue: Int, periodCount: Int) {
        guard isEligible, offerType == .introductory, paymentMode == .freeTrial,
              price == 0, periodValue > 0, periodCount == 1 else { return nil }
        switch periodUnit {
        case .day, .week, .month, .year: break
        @unknown default: return nil
        }
        self.periodValue = periodValue
        self.periodUnit = periodUnit
    }

    var durationDescription: String {
        var components = DateComponents()
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        switch periodUnit {
        case .day: components.day = periodValue; formatter.allowedUnits = [.day]
        case .week: components.weekOfMonth = periodValue; formatter.allowedUnits = [.weekOfMonth]
        case .month: components.month = periodValue; formatter.allowedUnits = [.month]
        case .year: components.year = periodValue; formatter.allowedUnits = [.year]
        @unknown default: return title
        }
        return formatter.string(from: components) ?? title
    }

    var title: String {
        switch periodUnit {
        case .day: String(localized: "\(periodValue)-day free trial")
        case .week: String(localized: "\(periodValue)-week free trial")
        case .month: String(localized: "\(periodValue)-month free trial")
        case .year: String(localized: "\(periodValue)-year free trial")
        @unknown default: String(localized: "Free trial")
        }
    }
}
#endif
