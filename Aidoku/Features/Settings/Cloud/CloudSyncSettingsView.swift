import CloudKit
import SwiftUI

@MainActor
struct CloudSyncSettingsView: View {
    @AppStorage("General.icloudSync") private var enabled = false
    @ObservedObject private var status = CloudSyncStatus.shared

    private var needsRestart: Bool { enabled != status.enabledAtLaunch }

    var body: some View {
        List {
            Section {
                Toggle("ICLOUD_SYNC_ENABLE", isOn: $enabled)
                    .disabled(!status.configured)
            } footer: {
                Text("ICLOUD_SYNC_SCOPE")
            }

            if needsRestart {
                Section {
                    Label("ICLOUD_SYNC_RESTART_REQUIRED", systemImage: "arrow.clockwise")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                if status.checkingAccount {
                    ProgressView("ICLOUD_SYNC_CHECKING")
                } else {
                    Text(accountMessage)
                }
                if status.enabledAtLaunch {
                    if status.activeEvents.isEmpty {
                        Label("ICLOUD_SYNC_ENABLED", systemImage: "icloud")
                    } else {
                        Label("ICLOUD_SYNC_ACTIVE", systemImage: "arrow.triangle.2.circlepath.icloud")
                    }
                    dateRow("ICLOUD_SYNC_LAST_UPLOAD", date: status.lastUpload)
                    dateRow("ICLOUD_SYNC_LAST_DOWNLOAD", date: status.lastDownload)
                } else {
                    Text("ICLOUD_SYNC_OFF")
                        .foregroundStyle(.secondary)
                }
                if let error = status.lastError {
                    Label(error, systemImage: "exclamationmark.icloud")
                        .foregroundStyle(.secondary)
                }
                Button("ICLOUD_SYNC_CHECK_ACCOUNT") {
                    Task { await status.refreshAccount() }
                }
                .disabled(status.checkingAccount)
            } header: {
                Text("ICLOUD_SYNC_STATUS")
            } footer: {
                Text("ICLOUD_SYNC_SCHEDULE_INFO")
            }

            Section {
                Text("ICLOUD_SYNC_REQUIREMENTS")
            }
        }
        .navigationTitle("ICLOUD_SYNC")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: enabled) { _ in
            NotificationCenter.default.post(name: .init(AppSettings.general.icloudSync.key), object: nil)
            status.preferencesChanged()
        }
        .task {
            status.start()
            await status.refreshAccount()
        }
    }

    private var accountMessage: LocalizedStringKey {
        guard status.configured else { return "ICLOUD_SYNC_CONFIGURATION_ERROR" }
        switch status.accountStatus {
            case .available:
                return "ICLOUD_SYNC_ACCOUNT_READY"
            case .noAccount:
                return "ICLOUD_SYNC_NO_ACCOUNT"
            case .restricted:
                return "ICLOUD_SYNC_RESTRICTED"
            case .temporarilyUnavailable, .couldNotDetermine, .none:
                return "ICLOUD_SYNC_ACCOUNT_UNAVAILABLE"
            @unknown default:
                return "ICLOUD_SYNC_ACCOUNT_UNAVAILABLE"
        }
    }

    private func dateRow(_ title: LocalizedStringKey, date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            if let date {
                Text(date, format: .dateTime.month().day().hour().minute())
                    .foregroundStyle(.secondary)
            } else {
                Text("ICLOUD_SYNC_NOT_YET")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
