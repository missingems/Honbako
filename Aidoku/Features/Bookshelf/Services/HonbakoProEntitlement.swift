#if SUMI
import Foundation

struct HonbakoProEntitlement: Codable, Equatable, Sendable {
    let productID: String
    let expirationDate: Date?
    let revocationDate: Date?
    let verifiedAt: Date

    func isActive(at date: Date, productID expected: String) -> Bool {
        productID == expected && revocationDate == nil
            && (expirationDate.map { $0 > date } ?? true)
            && verifiedAt <= date && date.timeIntervalSince(verifiedAt) < 30 * 86_400
    }
}
#endif
