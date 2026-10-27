#if targetEnvironment(simulator)
@testable import Sumi
import Foundation
import StoreKit
import StoreKitTest
import Testing

@MainActor
@Suite(.serialized)
struct HonbakoStoreKitIntegrationTests {
    private final class BundleMarker: NSObject {}

    @Test("A verified monthly StoreKit test purchase unlocks Pro, and refund removes the entitlement")
    func verifiedMonthlySubscription() async throws {
        let bundle = Bundle(for: BundleMarker.self)
        let url = try #require(bundle.url(forResource: "HonbakoPro", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        let store = HonbakoProStore.shared
        defer {
            session.clearTransactions()
            Task { @MainActor in await store.refreshEntitlement() }
        }
        await store.refreshEntitlement()
        #expect(!store.hasPro)
        // Activating the local StoreKit daemon and invalidating an earlier
        // empty product response are asynchronous on a freshly booted runtime.
        let catalogDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        repeat {
            await store.loadProduct()
            if store.product != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < catalogDeadline
        let rawCatalog = try await Product.products(for: [HonbakoProStore.productID])
        let catalogDescription = rawCatalog.map {
            "\($0.id): type=\($0.type), period=\(String(describing: $0.subscription?.subscriptionPeriod))"
        }.joined(separator: "; ")
        let product = try #require(store.product, "Local StoreKit catalog: \(catalogDescription); message: \(store.message ?? "none")")
        #expect(product.type == .autoRenewable)
        #expect(product.subscription?.subscriptionPeriod.value == 1)
        #expect(product.subscription?.subscriptionPeriod.unit == .month)
        let transaction = try await session.buyProduct(identifier: HonbakoProStore.productID)
        #expect(transaction.expirationDate != nil)
        for _ in 0..<50 {
            await store.refreshEntitlement()
            if store.hasPro { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(store.hasPro, "The real verified StoreKit entitlement path is used, not a debug unlock")
        #expect(HonbakoProStore.cachedHasPro)
        await transaction.finish()
        try session.refundTransaction(identifier: UInt(transaction.id))
        for _ in 0..<50 {
            await store.refreshEntitlement()
            if !store.hasPro { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!store.hasPro)
        #expect(!HonbakoProStore.cachedHasPro)
    }
}
#endif
