#if SUMI
import SwiftUI

struct HonbakoProView: View {
    let feature: HonbakoProFeature?
    @ObservedObject private var store = HonbakoProStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(feature.map { "\($0.title) is included with Honbako Pro." } ?? "More ways to keep your reading with you.")
                    Label("Download chapters for offline reading", systemImage: "arrow.down.circle")
                    Label("New chapter notifications", systemImage: "bell")
                    Label("Sync library and reading progress with iCloud", systemImage: "icloud")
                }
                Section {
                    if store.hasPro {
                        Label("Pro Is Active", systemImage: "checkmark.circle")
                    } else if let product = store.product {
                        Button("Get Pro · \(product.displayPrice)") { Task { await store.purchase() } }
                            .disabled(store.isLoading)
                    } else if store.isLoading { ProgressView("Checking the App Store…") }
                    if let message = store.message { Text(message).foregroundStyle(.secondary) }
                    Button("Restore Purchases") { Task { await store.restore() } }.disabled(store.isLoading)
                } footer: {
                    Text("Notifications depend on source availability and iOS background refresh. iCloud sync starts after reopening the app. Pro doesn’t include manga or grant rights to download third-party content.")
                }
            }
            .navigationTitle("Honbako Pro")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await store.loadProduct() }
        }
        .tint(.primary)
    }
}
#endif
