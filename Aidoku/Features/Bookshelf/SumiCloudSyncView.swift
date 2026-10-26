#if SUMI
import CloudKit
import SwiftUI

struct SumiCloudSyncView: View {
    @ObservedObject private var status = CloudSyncStatus.shared
    @ObservedObject private var pro = HonbakoProStore.shared
    @State private var proPresented = false

    var body: some View {
        List {
            Section {
                Label(message, systemImage: status.activeEvents.isEmpty ? "icloud" : "arrow.triangle.2.circlepath.icloud")
                if pro.hasPro, let error = status.lastError {
                    Text(error).foregroundStyle(.secondary)
                }
                if !pro.hasPro {
                    Button("View Honbako Pro") { proPresented = true }
                }
            } footer: {
                Text("Library, bookmarks, language choices, and reading progress sync with your iCloud account. Downloads and source files stay on this device.")
            }
            if pro.hasPro, let upload = status.lastUpload {
                LabeledContent("Last Upload") { Text(upload, format: .dateTime.month().day().hour().minute()) }
            }
            if pro.hasPro, let download = status.lastDownload {
                LabeledContent("Last Download") { Text(download, format: .dateTime.month().day().hour().minute()) }
            }
            if pro.hasPro {
                Button("Check iCloud Account") { Task { await status.refreshAccount() } }
                    .disabled(status.checkingAccount)
            }
        }
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $proPresented) { HonbakoProView(feature: .cloudProgress) }
        .task { if pro.hasPro { status.start(); await status.refreshAccount() } }
        .onChange(of: pro.hasPro) { _, enabled in
            if enabled { Task { status.start(); await status.refreshAccount() } }
        }
    }

    private var message: String {
        if !pro.hasPro { return "iCloud Sync Is Included with Honbako Pro" }
        if !status.configured { return "iCloud is unavailable in this build." }
        if status.checkingAccount { return "Checking iCloud…" }
        if !status.enabledAtLaunch { return "Reopen Honbako to enable automatic sync." }
        switch status.accountStatus {
        case .available:
            return status.activeEvents.isEmpty ? "Automatic Sync On" : "Syncing…"
        case .noAccount: return "Sign in to iCloud in Settings."
        case .restricted: return "iCloud access is restricted on this device."
        default: return "Waiting for iCloud. Your reading is saved on this device."
        }
    }
}
#endif
