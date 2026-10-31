#if SUMI
import SwiftUI

/// Source packages and credentials are deliberately separate from library metadata.
struct HonbakoSourceSetupRecoverySection: View {
    @State private var sync = HonbakoSourceSetupSync.shared
    @State private var connection: HonbakoSourceSetupRecord?
    let syncEnabled: Bool

    var body: some View {
        Group {
            if syncEnabled {
                Section {
                    if sync.isChecking {
                        Label { Text("Checking connection details…") } icon: { ProgressView() }
                    }
                    if sync.missing.isEmpty {
                        Label(sync.cloudAvailable ? "Connection details sync with iCloud" : "Waiting for iCloud connection details", systemImage: "externaldrive.badge.icloud")
                    }
                    ForEach(sync.missing) { item in
                        HonbakoSourceSetupRecoveryRow(item: item, sync: sync)
                    }
                    if !sync.missing.isEmpty {
                        NavigationLink("Personal Server") { SumiPersonalLibrariesView() }
                        #if HONBAKO_EXTERNAL_SOURCES
                        NavigationLink("Extension repositories") { SumiSourceListsView() }
                        #endif
                    }
                    if let message = sync.lastError { Text(message).foregroundStyle(.secondary) }
                    Button("Check Connection Details", systemImage: "arrow.clockwise") { Task { await sync.refresh() } }
                        .disabled(sync.isChecking)
                        .accessibilityIdentifier("Honbako.iCloud.CheckSourceSetup")
                } header: {
                    #if HONBAKO_EXTERNAL_SOURCES
                    Text("Sources and Extension Repositories")
                    #else
                    Text("Source Connections")
                    #endif
                } footer: {
                    #if HONBAKO_EXTERNAL_SOURCES
                    Text("Safe connection details and extension repository addresses sync with iCloud. Passwords, sign-in tokens, downloads, imported files, and extension packages stay on this device. Extensions are restored only when you choose Restore.")
                    #else
                    Text("Personal-server addresses and connection names sync with iCloud. Passwords, sign-in tokens, downloads, and imported files stay on each device. Open a personal-server connection here when it needs a local sign-in.")
                    #endif
                }
                if !sync.personalServers.isEmpty {
                    Section {
                        ForEach(sync.personalServers) { record in
                            Button { connection = record } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.name)
                                    Text(record.serverURL.flatMap { URL(string: $0)?.host } ?? record.kind.rawValue.capitalized)
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: { Text("Personal Servers") }
                    footer: { Text("Open a connection to sign in on this device. Passwords and tokens are never restored from the connection backup.") }
                }
            }
        }
        // No real cloud writer starts in unit, UI-test or screenshot fixture launches.
        .task { sync.start(); await sync.refresh() }
        .sheet(item: $connection) { record in HonbakoSourceReconnectView(sourceID: record.id) }
    }
}
#endif
