#if SUMI
import Foundation

/// Personal access is a build option embedded in the signed app, never a
/// runtime preference or a substitute for a verified App Store transaction.
enum HonbakoProAccessPolicy {
    static let personalFeaturesInfoKey = "HonbakoPersonalFeatures"

    static func personalFeaturesEnabled(infoDictionary: [String: Any]?) -> Bool {
        infoDictionary?[personalFeaturesInfoKey] as? String == "YES"
    }

    static func hasPro(personalFeaturesEnabled: Bool, verifiedEntitlement: HonbakoProEntitlement?,
                       at date: Date, productID: String) -> Bool {
        personalFeaturesEnabled || verifiedEntitlement?.isActive(at: date, productID: productID) == true
    }
}
#endif
