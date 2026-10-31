#if SUMI
import Foundation

enum HonbakoSubscriptionPricing {
    /// Round down so the displayed saving never exceeds the localized prices.
    static func saving(monthly: Decimal, annual: Decimal) -> Int? {
        let monthlyYear = monthly * 12
        guard monthlyYear > 0, annual > 0, annual < monthlyYear else { return nil }
        let percent = NSDecimalNumber(decimal: (monthlyYear - annual) / monthlyYear * 100).doubleValue
        guard percent.isFinite, percent >= 1, percent < 100 else { return nil }
        return Int(percent.rounded(.down))
    }
}
#endif
