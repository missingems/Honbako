@testable import Sumi
import Foundation
import Testing

struct HonbakoProEntitlementTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let product = "com.missingems.honbaku.pro"

    @Test("Only a recent verified, unexpired monthly subscription claim grants cached access")
    func verifiedClaims() {
        func claim(id: String? = nil, expires: Date? = .distantFuture, revoked: Date? = nil, verified: Date? = nil) -> HonbakoProEntitlement {
            .init(productID: id ?? product, expirationDate: expires, revocationDate: revoked, verifiedAt: verified ?? now)
        }
        #expect(!claim(expires: nil).isActive(at: now, productID: product), "Perpetual or incomplete claims do not grant monthly Pro")
        #expect(claim(expires: now.addingTimeInterval(60)).isActive(at: now, productID: product))
        #expect(claim(expires: now.addingTimeInterval(60), verified: now.addingTimeInterval(-31 * 86_400)).isActive(at: now, productID: product), "A 31-day monthly period is not cut off by a 30-day cache limit")
        #expect(!claim(id: "another.product").isActive(at: now, productID: product))
        #expect(!claim(expires: now).isActive(at: now, productID: product))
        #expect(!claim(revoked: now.addingTimeInterval(-1)).isActive(at: now, productID: product))
        #expect(!claim(verified: now.addingTimeInterval(-33 * 86_400)).isActive(at: now, productID: product))
        #expect(!claim(verified: now.addingTimeInterval(1)).isActive(at: now, productID: product))
    }
}
