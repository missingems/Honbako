#if SUMI
import SwiftUI

/// Describes the current data flow without claiming an unapproved public policy.
struct HonbakoPrivacyInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Your Library") {
                    Text("Your library, chapter history, bookmarks, and preferences are stored on this device. Downloaded pages and source files stay on this device.")
                }
                Section("Connections You Choose") {
                    Text("Searches, manga identifiers, and image requests are sent to the sources or personal servers you connect. Those providers receive network information such as your IP address and may have their own privacy policies.")
                }
                Section("iCloud Sync") {
                    Text("With Pro, library metadata and reading progress can sync through your private iCloud database. Reading progress includes the device name and a device identifier so your devices can identify the saved place.")
                }
                Section("Purchases and Notifications") {
                    Text("Apple processes Pro payments. Honbako verifies StoreKit transactions to determine your subscription status. Chapter alerts use notification permission and iOS background refresh.")
                }
                Section("Tracking") {
                    Text("Honbako has no advertising or analytics SDK. It does not use the advertising identifier or track you across other companies’ apps and websites.")
                }
            }
            .navigationTitle("Privacy Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(.primary)
    }
}
#endif
