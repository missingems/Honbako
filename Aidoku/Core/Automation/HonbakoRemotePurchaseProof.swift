#if SUMI
import Foundation
import StoreKit

/// Hosting is routed only after StoreKit verifies an active subscription.
/// A build flag, cached Pro access, or a decoded JWS payload cannot select it.
struct HonbakoRemotePurchaseProof: Equatable, Sendable {
    let signedTransaction: String
    let environment: AppStore.Environment
    let endpoint: URL

    init?(verification: VerificationResult<Transaction>, at date: Date = .now) {
        guard case .verified(let transaction) = verification,
              HonbakoProStore.productIDs.contains(transaction.productID),
              transaction.productType == .autoRenewable,
              transaction.revocationDate == nil,
              transaction.expirationDate.map({ $0 > date }) == true,
              let endpoint = HonbakoRemoteMCP.endpoint(forVerifiedEnvironment: transaction.environment) else { return nil }
        signedTransaction = verification.jwsRepresentation
        environment = transaction.environment
        self.endpoint = endpoint
    }
}
#endif
