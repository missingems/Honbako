#if SUMI
import Combine
import Foundation
import StoreKit

@MainActor
final class HonbakoProStore: ObservableObject {
    static let shared = HonbakoProStore()
    nonisolated static let productID = "com.missingems.honbaku.pro"
    nonisolated static let entitlementChangedNotification = Notification.Name("Honbako.Pro.EntitlementChanged")
    nonisolated private static let cacheKey = "Honbako.Pro.VerifiedEntitlement.v1"
    @Published private(set) var hasPro = cachedHasPro
    @Published private(set) var product: Product?
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    private var listener: Task<Void, Never>?

    nonisolated static var personalFeaturesEnabled: Bool {
        HonbakoProAccessPolicy.personalFeaturesEnabled(infoDictionary: Bundle.main.infoDictionary)
    }

    nonisolated static var cachedHasPro: Bool {
        let claim = UserDefaults.standard.data(forKey: cacheKey).flatMap {
            try? JSONDecoder().decode(HonbakoProEntitlement.self, from: $0)
        }
        return HonbakoProAccessPolicy.hasPro(personalFeaturesEnabled: personalFeaturesEnabled,
            verifiedEntitlement: claim, at: .now, productID: productID)
    }

    func start() {
        guard listener == nil else { return }
        listener = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                if case .verified(let transaction) = result, transaction.productID == Self.productID {
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
            product = try await Product.products(for: [Self.productID]).first {
                $0.type == .autoRenewable
                    && $0.subscription?.subscriptionPeriod.unit == .month
                    && $0.subscription?.subscriptionPeriod.value == 1
            }
            message = product == nil ? String(localized: "Monthly Pro purchases aren’t available yet. Reading your library remains free.") : nil
        } catch {
            message = String(localized: "The App Store couldn’t be reached. Try again later.")
        }
    }

    func refreshEntitlement() async {
        var active: HonbakoProEntitlement?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.productID == Self.productID,
                  transaction.productType == .autoRenewable else { continue }
            let claim = HonbakoProEntitlement(productID: transaction.productID,
                expirationDate: transaction.expirationDate, revocationDate: transaction.revocationDate, verifiedAt: .now)
            if claim.isActive(at: .now, productID: Self.productID) { active = claim; break }
        }
        if let active, let data = try? JSONEncoder().encode(active) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.cacheKey) }
        let enabled = HonbakoProAccessPolicy.hasPro(personalFeaturesEnabled: Self.personalFeaturesEnabled,
            verifiedEntitlement: active, at: .now, productID: Self.productID)
        if hasPro != enabled {
            hasPro = enabled
            NotificationCenter.default.post(name: Self.entitlementChangedNotification, object: enabled)
        }
    }

    func purchase() async {
        guard !Self.personalFeaturesEnabled, !isLoading, let product else { return }
        isLoading = true
        defer { isLoading = false }
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
