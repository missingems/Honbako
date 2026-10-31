#if SUMI
import Combine
import Foundation
import StoreKit

@MainActor
final class HonbakoProStore: ObservableObject {
    static let shared = HonbakoProStore()
    nonisolated static let productID = "com.missingems.honbaku.pro"
    nonisolated static let annualProductID = "com.missingems.honbaku.pro.annual"
    nonisolated static let productIDs: Set<String> = [productID, annualProductID]
    nonisolated static let entitlementChangedNotification = Notification.Name("Honbako.Pro.EntitlementChanged")
    nonisolated private static let cacheKey = "Honbako.Pro.VerifiedEntitlement.v1"
    @Published private(set) var hasPro = cachedHasPro
    @Published private(set) var hasVerifiedPro = false
    @Published private(set) var hasCheckedEntitlement = false
    @Published private(set) var activeEntitlement: HonbakoProEntitlement? = cachedEntitlement
    @Published private(set) var product: Product?
    @Published private(set) var annualProduct: Product?
    @Published private(set) var introductoryTrials: [String: HonbakoSubscriptionTrial] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    private var listener: Task<Void, Never>?
    private var introOfferGeneration = 0

    nonisolated static var personalFeaturesEnabled: Bool {
        HonbakoProAccessPolicy.personalFeaturesEnabled(infoDictionary: Bundle.main.infoDictionary)
    }

    nonisolated private static var cachedEntitlement: HonbakoProEntitlement? {
        UserDefaults.standard.data(forKey: cacheKey).flatMap {
            try? JSONDecoder().decode(HonbakoProEntitlement.self, from: $0)
        }
    }

    nonisolated static var cachedHasPro: Bool {
        let claim = cachedEntitlement
        return HonbakoProAccessPolicy.hasPro(personalFeaturesEnabled: personalFeaturesEnabled,
            verifiedEntitlement: claim, at: .now, productID: claim.flatMap { productIDs.contains($0.productID) ? $0.productID : nil } ?? productID)
    }

    var widgetAccessExpiration: Date? {
        if Self.personalFeaturesEnabled { return .distantFuture }
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let claim = try? JSONDecoder().decode(HonbakoProEntitlement.self, from: data),
              Self.productIDs.contains(claim.productID), claim.isActive(at: .now, productID: claim.productID) else { return nil }
        return claim.expirationDate
    }

    func start() {
        guard listener == nil else { return }
        listener = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                if case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID) {
                    await self?.refreshEntitlement()
                    await transaction.finish()
                }
            }
        }
        Task { await refreshEntitlement() }
    }

    func loadProduct() async {
        guard !Self.personalFeaturesEnabled, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let available = try await Product.products(for: Array(Self.productIDs))
            product = available.first {
                $0.id == Self.productID && $0.type == .autoRenewable
                    && $0.subscription?.subscriptionPeriod.unit == .month && $0.subscription?.subscriptionPeriod.value == 1
            }
            annualProduct = available.first {
                $0.id == Self.annualProductID && $0.type == .autoRenewable
                    && $0.subscription?.subscriptionPeriod.unit == .year && $0.subscription?.subscriptionPeriod.value == 1
            }
            await refreshIntroductoryOffers()
            message = product == nil && annualProduct == nil ? String(localized: "Pro purchases aren’t available yet. Reading your library remains free.") : nil
        } catch {
            introductoryTrials = [:]
            introOfferGeneration += 1
            message = String(localized: "The App Store couldn’t be reached. Try again later.")
        }
    }

    /// An offer requires Apple's eligibility and no verified introductory
    /// redemption in the same Pro group, including expired subscriptions.
    func refreshIntroductoryOffers() async {
        introOfferGeneration += 1
        let generation = introOfferGeneration
        introductoryTrials = [:]
        guard !hasPro else { return }
        let availableProducts = [product, annualProduct].compactMap { $0 }
        let availableGroups = Set(availableProducts.compactMap { $0.subscription?.subscriptionGroupID })
        guard !availableGroups.isEmpty else { return }
        var redeemedGroups: Set<String> = []
        // Current entitlements omit expired trials. Verified history provides
        // independent evidence when StoreKit returns stale eligibility metadata.
        for await result in Transaction.all {
            guard generation == introOfferGeneration, !hasPro else { return }
            guard case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID),
                  transaction.productType == .autoRenewable, transaction.offer?.type == .introductory,
                  let groupID = transaction.subscriptionGroupID, availableGroups.contains(groupID) else { continue }
            redeemedGroups.insert(groupID)
            if redeemedGroups == availableGroups { break }
        }
        var trials: [String: HonbakoSubscriptionTrial] = [:]
        for product in availableProducts {
            guard let subscription = product.subscription, !redeemedGroups.contains(subscription.subscriptionGroupID),
                  let offer = subscription.introductoryOffer else { continue }
            let eligible = await subscription.isEligibleForIntroOffer
            guard generation == introOfferGeneration else { return }
            if let trial = HonbakoSubscriptionTrial(offer: offer, isEligible: eligible) { trials[product.id] = trial }
        }
        guard generation == introOfferGeneration, !hasPro else { return }
        introductoryTrials = trials
    }

    func refreshEntitlement() async {
        var active: HonbakoProEntitlement?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID),
                  transaction.productType == .autoRenewable else { continue }
            let claim = HonbakoProEntitlement(productID: transaction.productID,
                expirationDate: transaction.expirationDate, revocationDate: transaction.revocationDate, verifiedAt: .now)
            if claim.isActive(at: .now, productID: transaction.productID) { active = claim; break }
        }
        if let active, let data = try? JSONEncoder().encode(active) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.cacheKey) }
        let enabled = HonbakoProAccessPolicy.hasPro(personalFeaturesEnabled: Self.personalFeaturesEnabled,
            verifiedEntitlement: active, at: .now, productID: active?.productID ?? Self.productID)
        NotificationCenter.default.post(name: .init("Honbako.Widgets.Entitlement"), object: nil)
        let remoteEnabled = active != nil
        let changed = hasPro != enabled || hasVerifiedPro != remoteEnabled
        activeEntitlement = active
        hasCheckedEntitlement = true
        hasVerifiedPro = remoteEnabled
        if changed {
            hasPro = enabled
            NotificationCenter.default.post(name: Self.entitlementChangedNotification, object: enabled)
        }
        await refreshIntroductoryOffers()
    }

    /// The signed StoreKit transaction is sent only to Honbako’s configured server.
    /// Personal-build access and cached booleans cannot unlock paid remote hosting.
    func remotePurchaseProof() async -> HonbakoRemotePurchaseProof? {
        for await result in Transaction.currentEntitlements {
            if let proof = HonbakoRemotePurchaseProof(verification: result) { return proof }
        }
        return nil
    }

    func purchase(plan: HonbakoSubscriptionPlan = .monthly) async {
        guard !Self.personalFeaturesEnabled, !isLoading,
              let product = plan == .monthly ? product : annualProduct else { return }
        let displayedTrial = introductoryTrials[product.id]
        isLoading = true
        defer { isLoading = false }
        await refreshEntitlement()
        guard !hasPro else { return }
        guard displayedTrial == nil || introductoryTrials[product.id] == displayedTrial else {
            message = String(localized: "Your free-trial eligibility changed. Review the current plan price before continuing.")
            return
        }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    message = String(localized: "This purchase couldn’t be verified. No Pro features were unlocked.")
                    return
                }
                await refreshEntitlement()
                await transaction.finish()
                message = nil
            case .pending: message = String(localized: "Your purchase is awaiting approval.")
            case .userCancelled: break
            @unknown default: message = String(localized: "The purchase didn’t complete. Try again later.")
            }
        } catch { message = String(localized: "The purchase didn’t complete. \(error.localizedDescription)") }
    }

    func restore() async {
        guard !Self.personalFeaturesEnabled, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            message = hasPro ? String(localized: "Pro purchases restored.") : String(localized: "No active Pro purchase was found.")
        } catch { message = String(localized: "Purchases couldn’t be restored. Try again later.") }
    }

    deinit { listener?.cancel() }
}
#endif
