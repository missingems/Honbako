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

    @Test("Verified monthly and annual StoreKit purchases unlock Pro, and refund removes the entitlement", arguments: [false, true])
    func verifiedSubscription(annual: Bool) async throws {
        try #require(ProcessInfo.processInfo.arguments.contains("--honbako-storekit-tests"),
            "Use the HonbakoStoreKitTests scheme to initialize the local StoreKit session before the app starts its store.")
        let expectedID = annual ? HonbakoProStore.annualProductID : HonbakoProStore.productID
        let bundle = Bundle(for: BundleMarker.self)
        let url = try #require(bundle.url(forResource: "HonbakoPro", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        let store = HonbakoProStore.shared
        store.start()
        defer {
            session.clearTransactions()
            Task { @MainActor in await store.refreshEntitlement() }
        }
        await store.refreshEntitlement()
        #expect(!store.hasPro)
        #expect(!store.hasVerifiedPro)
        #expect(await store.remotePurchaseProof() == nil)
        // Activating the local StoreKit daemon and invalidating an earlier
        // empty product response are asynchronous on a freshly booted runtime.
        let catalogDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        repeat {
            await store.loadProduct()
            if (annual ? store.annualProduct : store.product) != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < catalogDeadline
        let rawCatalog = try await Product.products(for: [expectedID])
        let catalogDescription = rawCatalog.map {
            "\($0.id): type=\($0.type), period=\(String(describing: $0.subscription?.subscriptionPeriod))"
        }.joined(separator: "; ")
        let product = try #require(annual ? store.annualProduct : store.product, "Local StoreKit catalog: \(catalogDescription); message: \(store.message ?? "none")")
        try #require(product.subscription?.subscriptionGroupID == "7AFB68E2",
            "Run this test with the HonbakoStoreKitTests scheme so StoreKit uses the local fixture before app launch.")
        #expect(product.type == .autoRenewable)
        #expect(product.subscription?.subscriptionPeriod.value == 1)
        #expect(product.subscription?.subscriptionPeriod.unit == (annual ? .year : .month))
        let transaction = try await session.buyProduct(identifier: expectedID)
        #expect(transaction.expirationDate != nil)
        for _ in 0..<50 {
            await store.refreshEntitlement()
            if store.hasPro { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(store.hasPro, "The real verified StoreKit entitlement path is used, not a debug unlock")
        #expect(HonbakoProStore.cachedHasPro)
        #expect(store.hasVerifiedPro)
        #expect(HonbakoWelcomeGate.shouldPresent(completedVersion: 0, hasPreviewBooks: false,
            arguments: [], environment: [:]), "A restored subscription must not skip a new installation's introduction")
        #expect(!HonbakoWelcomeGate.shouldPresent(completedVersion: 2, hasPreviewBooks: false,
            arguments: [], environment: [:]), "An ordinary update must respect completed onboarding")
        #expect(await store.remotePurchaseProof() == nil, "Xcode StoreKit test entitlements unlock local Pro, but cannot grant either remote environment")
        await transaction.finish()
        try session.refundTransaction(identifier: UInt(transaction.id))
        for _ in 0..<50 {
            await store.refreshEntitlement()
            if !store.hasPro { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!store.hasPro)
        #expect(!HonbakoProStore.cachedHasPro)
        #expect(!store.hasVerifiedPro)
        #expect(await store.remotePurchaseProof() == nil)
    }
    @Test("Apple trial metadata is used only for eligible subscribers and cannot be claimed twice within the Pro group")
    func introductoryTrialEligibility() async throws {
        try #require(ProcessInfo.processInfo.arguments.contains("--honbako-storekit-tests"))
        let bundledURL = try #require(Bundle(for: BundleMarker.self).url(forResource: "HonbakoPro", withExtension: "storekit"))
        // StoreKit caches introductory eligibility by subscription group within
        // the process even after clearTransactions. Use a new local group for
        // this scenario while preserving the real allowlisted product IDs.
        let groupID = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
        var fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: bundledURL)) as? [String: Any])
        var groups = try #require(fixture["subscriptionGroups"] as? [[String: Any]])
        try #require(groups.count == 1)
        groups[0]["id"] = groupID
        var subscriptions = try #require(groups[0]["subscriptions"] as? [[String: Any]])
        for index in subscriptions.indices { subscriptions[index]["subscriptionGroupID"] = groupID }
        groups[0]["subscriptions"] = subscriptions
        fixture["subscriptionGroups"] = groups
        fixture["identifier"] = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HonbakoTrial-\(UUID().uuidString).storekit")
        try JSONSerialization.data(withJSONObject: fixture).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        let store = HonbakoProStore.shared
        defer {
            session.clearTransactions()
            Task { @MainActor in await store.refreshEntitlement(); await store.loadProduct() }
        }
        await store.refreshEntitlement()
        var products: [Product] = []
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        repeat {
            products = try await Product.products(for: Array(HonbakoProStore.productIDs))
            if products.count == 2, products.allSatisfy({
                $0.subscription?.subscriptionGroupID == groupID && $0.subscription?.introductoryOffer != nil
            }), await Product.SubscriptionInfo.isEligibleForIntroOffer(for: groupID) { break }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < deadline
        let monthly = try #require(products.first { $0.id == HonbakoProStore.productID })
        let annual = try #require(products.first { $0.id == HonbakoProStore.annualProductID })
        let monthInfo = try #require(monthly.subscription)
        let yearInfo = try #require(annual.subscription)
        try #require(monthInfo.subscriptionGroupID == groupID,
                     "The local catalog must switch to this scenario's fresh subscription group before checking eligibility")
        #expect(monthInfo.subscriptionGroupID == yearInfo.subscriptionGroupID)
        for (info, expectedUnit) in [(monthInfo, Product.SubscriptionPeriod.Unit.week), (yearInfo, .month)] {
            let offer = try #require(info.introductoryOffer, "The fixture must produce a real StoreKit introductory offer")
            #expect(offer.type == .introductory)
            #expect(offer.paymentMode == .freeTrial)
            #expect(offer.price == 0)
            #expect(offer.periodCount == 1)
            #expect(offer.period.value == 1)
            #expect(offer.period.unit == expectedUnit)
            let isEligible = await info.isEligibleForIntroOffer
            #expect(isEligible)
            #expect(HonbakoSubscriptionTrial(offer: offer, isEligible: isEligible)?.periodUnit == expectedUnit)
            #expect(HonbakoSubscriptionTrial(offer: offer, isEligible: false) == nil)
        }
        await store.loadProduct()
        #expect(store.introductoryTrials[monthly.id]?.periodUnit == .week)
        #expect(store.introductoryTrials[annual.id]?.periodUnit == .month)

        let first = try await session.buyProduct(identifier: monthly.id)
        #expect(first.offer?.type == .introductory)
        #expect(first.subscriptionGroupID == groupID)
        await first.finish()
        await store.refreshEntitlement()
        await store.loadProduct()
        #expect(store.hasVerifiedPro)
        #expect(store.introductoryTrials.isEmpty, "Neither plan may advertise a second trial after using the monthly offer")
        try session.expireSubscription(productIdentifier: monthly.id)
        // Check consumed eligibility after the first subscription expires, so
        // an active entitlement cannot conceal an incorrectly offered trial.
        // Synchronize the local StoreKit transaction history before querying
        // the group again; retaining an earlier Product is not a cache reset.
        try await AppStore.sync()
        var eligibleForAnotherTrial = true
        let eligibilityDeadline = ContinuousClock.now.advanced(by: .seconds(10))
        repeat {
            let refreshed = try await Product.products(for: [annual.id])
            let refreshedAnnual = try #require(refreshed.first { $0.id == annual.id })
            let refreshedGroup = try #require(refreshedAnnual.subscription?.subscriptionGroupID)
            try #require(refreshedGroup == groupID)
            eligibleForAnotherTrial = await Product.SubscriptionInfo.isEligibleForIntroOffer(for: refreshedGroup)
            if !eligibleForAnotherTrial { break }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < eligibilityDeadline
        let runtime = ProcessInfo.processInfo.operatingSystemVersion
        if runtime.majorVersion == 27, runtime.minorVersion == 0 {
            // Local StoreKit eligibility can remain cached after test-history
            // resets on 27.0 (FB24137836; fixed in 27.2). Only Apple's raw
            // response is covered; verified history and app behavior must pass.
            // https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27_2-release-notes
            withKnownIssue("FB24137836: local StoreKit introductory-eligibility cache after test-history resets", isIntermittent: true) {
                #expect(!eligibleForAnotherTrial, "An expired monthly introductory trial consumes eligibility for the whole subscription group")
            }
        } else {
            #expect(!eligibleForAnotherTrial, "An expired monthly introductory trial consumes eligibility for the whole subscription group")
        }
        var verifiedTrialInHistory = false
        for await result in Transaction.all {
            if case .verified(let transaction) = result, transaction.productID == monthly.id,
               transaction.subscriptionGroupID == groupID, transaction.offer?.type == .introductory {
                verifiedTrialInHistory = true
                break
            }
        }
        try #require(verifiedTrialInHistory, "The consumed trial must be backed by verified StoreKit history, not a local eligibility flag")
        await store.refreshEntitlement()
        await store.loadProduct()
        #expect(!store.hasVerifiedPro)
        #expect(store.introductoryTrials.isEmpty, "An expired subscriber must not be offered another trial on either plan")
        let second = try await session.buyProduct(identifier: annual.id)
        #expect(second.offer?.type != .introductory, "Switching to annual must use ordinary billing, not a second free trial")
        await second.finish()
    }

}
#endif
