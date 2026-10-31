#if SUMI
import SwiftUI

/// Describes the current data flow without claiming an unapproved public policy.
struct HonbakoPrivacyInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section("Your Library") {
                        Text("Your library, chapter history, bookmarks, and preferences are stored on this device. Downloaded pages and source files stay on this device.")
                    }
                    Section("Connections You Choose") {
                        Text("Searches, manga identifiers, and image requests are sent to the sources or personal servers you connect. Those providers receive network information such as your IP address and may have their own privacy policies.")
                    }
                    Section("iCloud Sync") {
                        Text("Library metadata and reading progress can sync through your private iCloud database. Reading progress includes the device name and a device identifier so your devices can identify the saved place.")
                    }
                    Section("Purchases and Notifications") {
                        Text("Apple processes Pro payments. Honbako verifies StoreKit transactions to determine your subscription status. Chapter alerts use notification permission and iOS background refresh.")
                    }
                    Section("MCP Server") {
                        Text("If you enable remote MCP, Honbako’s hosted service stores the library and reading details you share, queued requests, and your last shared manga page. AI connections you approve can access that workspace. Pro verification sends your signed purchase to Honbako and checks it with Apple. Your own AI provider handles its model usage under its policies.")
                        Text("Turning off MCP while connected removes the shared library, requests and page from the server and revokes its AI access. Minimal installation and purchase hashes remain to protect the workspace and prevent hosting abuse. If the server cannot be reached, deletion may need another connected attempt. Removing the app alone does not delete remote data.")
                    }
                    Section("Tracking") {
                        Text("Honbako has no advertising or analytics SDK. It does not use the advertising identifier or track you across other companies’ apps and websites.")
                    }
                }
                .honbakoPaperRows()
            }
            .honbakoPaperListBackground()
            .navigationTitle("Privacy Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(.primary)
    }
}
#endif
