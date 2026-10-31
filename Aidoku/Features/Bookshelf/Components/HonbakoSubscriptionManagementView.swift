#if SUMI
import StoreKit
import SwiftUI

struct HonbakoSubscriptionManagementView: View {
    var continueReading: (() -> Void)?
    @ObservedObject private var store = HonbakoProStore.shared
    @State private var managingSubscription = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Group {
                Section {
                    Label("Pro Is Active", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .accessibilityIdentifier("Honbako.Subscription.Active")
                    if let entitlement = store.activeEntitlement {
                        LabeledContent("Plan", value: entitlement.productID == HonbakoProStore.annualProductID
                            ? "Pro per year" : "Pro per month")
                        if let expiration = entitlement.expirationDate {
                            LabeledContent("Access Until") {
                                Text(expiration, format: .dateTime.day().month().year())
                            }
                        }
                    }
                }
                Section {
                    Button("Manage Subscription") { managingSubscription = true }
                        .accessibilityIdentifier("Honbako.Subscription.Manage")
                } footer: {
                    Text("Change your plan or cancel in your Apple Account. Your Pro access continues until the end of your current period.")
                }
                if let continueReading {
                    Section {
                        Button("Continue to Library", action: continueReading)
                            .accessibilityIdentifier("Honbako.Subscription.ContinueReading")
                    }
                }
            }
            .honbakoPaperRows()
        }
        .honbakoPaperListBackground()
        .manageSubscriptionsSheet(isPresented: $managingSubscription, subscriptionGroupID: "22521322")
        .onChange(of: managingSubscription) {
            if !managingSubscription { Task { await store.refreshEntitlement() } }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await store.refreshEntitlement() } }
        }
    }
}
#endif
