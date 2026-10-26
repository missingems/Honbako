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

    nonisolated static var cachedHasPro: Bool {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let claim = try? JSONDecoder().decode(HonbakoProEntitlement.self, from: data) else { return false }
        return claim.isActive(at: .now, productID: productID)
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
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            product = try await Product.products(for: [Self.productID]).first {
                $0.type == .nonConsumable || $0.type == .autoRenewable
            }
            message = product == nil ? "Pro purchases aren’t available yet. Reading your library remains free." : nil
        } catch {
            message = "The App Store couldn’t be reached. Try again later."
        }
    }

    func refreshEntitlement() async {
        var active: HonbakoProEntitlement?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.productID == Self.productID,
                  transaction.productType == .nonConsumable || transaction.productType == .autoRenewable else { continue }
            let claim = HonbakoProEntitlement(productID: transaction.productID,
                expirationDate: transaction.expirationDate, revocationDate: transaction.revocationDate, verifiedAt: .now)
            if claim.isActive(at: .now, productID: Self.productID) { active = claim; break }
        }
        if let active, let data = try? JSONEncoder().encode(active) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.cacheKey) }
        let enabled = active != nil
        if hasPro != enabled {
            hasPro = enabled
            NotificationCenter.default.post(name: Self.entitlementChangedNotification, object: enabled)
        }
    }

    func purchase() async {
        guard !isLoading, let product else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    message = "This purchase couldn’t be verified. No Pro features were unlocked."
                    return
                }
                await refreshEntitlement()
                await transaction.finish()
                message = nil
            case .pending: message = "Your purchase is awaiting approval."
            case .userCancelled: break
            @unknown default: message = "The purchase didn’t complete. Try again later."
            }
        } catch { message = "The purchase didn’t complete. \(error.localizedDescription)" }
    }

    func restore() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            message = hasPro ? "Pro purchases restored." : "No active Pro purchase was found."
        } catch { message = "Purchases couldn’t be restored. Try again later." }
    }

    deinit { listener?.cancel() }
}
#endif
