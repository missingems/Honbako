#if SUMI
import Foundation

struct HonbakoProEntitlement: Codable, Equatable, Sendable {
    let productID: String
    let expirationDate: Date?
    let revocationDate: Date?
    let verifiedAt: Date

    // Allow a full 31-day month (including clock/DST variation), while the
    // verified transaction expiry remains the strict entitlement boundary.
    func isActive(at date: Date, productID expected: String) -> Bool {
        productID == expected && revocationDate == nil
            && (expirationDate.map { $0 > date } ?? false)
            && verifiedAt <= date && date.timeIntervalSince(verifiedAt) < 32 * 86_400
    }
}
#endif
