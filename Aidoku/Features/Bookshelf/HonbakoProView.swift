#if SUMI
import SwiftUI

struct HonbakoProView: View {
    let feature: HonbakoProFeature?
    @ObservedObject private var store = HonbakoProStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var privacyPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(feature.map { String(localized: "\($0.title) is included with Honbako Pro.") } ?? String(localized: "More ways to keep your reading with you."))
                    Label("Download chapters for offline reading", systemImage: "arrow.down.circle")
                    Label("New chapter notifications", systemImage: "bell")
                    Label("Sync library and reading progress with iCloud", systemImage: "icloud")
                }
                Section {
                    if store.hasPro {
                        Label("Pro Is Active", systemImage: "checkmark.circle")
                    } else if let product = store.product {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.displayName).font(.headline)
                            Text("Monthly Subscription").font(.subheadline).foregroundStyle(.secondary)
                            Text("\(product.displayPrice) per month").font(.title2.bold())
                        }
                        Button("Subscribe") { Task { await store.purchase() } }
                            .disabled(store.isLoading)
                    } else if store.isLoading { ProgressView("Checking the App Store…") }
                    if let message = store.message { Text(message).foregroundStyle(.secondary) }
                    Button("Restore Purchases") { Task { await store.restore() } }.disabled(store.isLoading)
                    Link("Manage Subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                } footer: {
                    Text("Payment is charged to your Apple Account when confirmed. Your subscription renews monthly unless canceled. Manage or cancel it in App Store subscriptions.")
                }
                Section {
                    Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    Button("Privacy Information") { privacyPresented = true }
                } footer: {
                    Text("Notifications depend on source availability and iOS background refresh. iCloud sync starts after reopening the app. Pro doesn’t include manga or grant rights to download third-party content.")
                }
            }
            .navigationTitle("Honbako Pro")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await store.loadProduct() }
            .sheet(isPresented: $privacyPresented) { HonbakoPrivacyInfoView() }
        }
        .tint(.primary)
    }
}
#endif
