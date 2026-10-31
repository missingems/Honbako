#if SUMI
import CloudKit
import SwiftUI

struct SumiCloudSyncView: View {
    @ObservedObject private var status = CloudSyncStatus.shared
    @AppStorage("General.icloudSync") private var syncEnabled = true

    var body: some View {
        List {
            Group {
                Section {
                    Label(message, systemImage: status.activeEvents.isEmpty ? "icloud" : "arrow.triangle.2.circlepath.icloud")
                    Toggle("Sync with iCloud", isOn: $syncEnabled)
                        .accessibilityIdentifier("Honbako.iCloud.Enabled")
                    if let error = status.lastError {
                        Text(error).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Library, bookmarks, language choices, reading progress, and safe source connection details sync with your iCloud account. Downloads, extension packages, and sign-in credentials stay on this device.")
                }
                if let upload = status.lastUpload {
                    LabeledContent("Last Upload") { Text(upload, format: .dateTime.month().day().hour().minute()) }
                }
                if let download = status.lastDownload {
                    LabeledContent("Last Download") { Text(download, format: .dateTime.month().day().hour().minute()) }
                }
                HonbakoSourceSetupRecoverySection(syncEnabled: syncEnabled)
                Button("Check iCloud Account") { Task { await status.refreshAccount() } }
                    .disabled(status.checkingAccount)
            }
            .honbakoPaperRows()
        }
        .honbakoPaperListBackground()
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
        .tint(HonbakoPalette.accent)
        .task { status.start(); await status.refreshAccount() }
        .onChange(of: syncEnabled) { _, enabled in
            NotificationCenter.default.post(name: .init(AppSettings.general.icloudSync.key), object: enabled)
        }
    }

    private var message: String {
        if !syncEnabled {
            return status.enabledAtLaunch ? String(localized: "Reopen Honbako to turn off automatic sync.")
                : String(localized: "iCloud Sync Off")
        }
        if !status.configured { return String(localized: "iCloud is unavailable in this build.") }
        if status.checkingAccount { return String(localized: "Checking iCloud…") }
        if !status.enabledAtLaunch { return String(localized: "Reopen Honbako to enable automatic sync.") }
        switch status.accountStatus {
        case .available:
            return status.activeEvents.isEmpty ? String(localized: "Automatic Sync On") : String(localized: "Syncing…")
        case .noAccount: return String(localized: "Sign in to iCloud in Settings.")
        case .restricted: return String(localized: "iCloud access is restricted on this device.")
        default: return String(localized: "Waiting for iCloud. Your reading is saved on this device.")
        }
    }
}
#endif
