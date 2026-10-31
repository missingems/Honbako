#if SUMI
import Foundation

enum HonbakoSubscriptionPlan: String, CaseIterable, Identifiable {
    case monthly, annual
    var id: String { rawValue }
    var title: String { self == .monthly ? "Monthly" : "Annual" }
}
#endif
