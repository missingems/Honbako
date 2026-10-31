#if SUMI
import SwiftUI

struct HonbakoSourceSetupRecoveryRow: View {
    let item: HonbakoSourceSetupRecovery
    let sync: HonbakoSourceSetupSync
    @State private var showRestoreConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.name)
            if item.canReconnectBundledSource {
                Text("Your library is saved. Reconnect the built-in MangaDex source to load its covers and chapters again.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Reconnect MangaDex", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await sync.restore(item) }
                }
                .disabled(sync.restoringID != nil)
                .accessibilityIdentifier("Honbako.iCloud.ReconnectMangaDex")
            } else if item.canRestorePackage && supportsExtensionRecovery {
                Text("Version \(item.record?.version ?? 0) · \(packageHost)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Restore Extension", systemImage: "arrow.down.circle") { showRestoreConfirmation = true }
                    .disabled(sync.restoringID != nil || !sync.cloudAvailable)
                    .confirmationDialog("Restore this extension?", isPresented: $showRestoreConfirmation, titleVisibility: .visible) {
                        Button("Restore Extension") { Task { await sync.restore(item) } }
                    } message: {
                        Text("Download \(item.name) at its saved version from its original location. Extensions run on your device. Your existing connections and credentials will be kept.")
                    }
            } else {
                #if HONBAKO_EXTERNAL_SOURCES
                Text("This library source isn’t installed. Its original connection details weren’t saved to iCloud. Reconnect your personal server or add its original extension repository.")
                    .font(.subheadline).foregroundStyle(.secondary)
                #else
                Text("This library source isn’t configured on this device. Reconnect the matching personal server. Files from another device need to be imported again.")
                    .font(.subheadline).foregroundStyle(.secondary)
                #endif
            }
            if sync.restoringID == item.id { ProgressView("Restoring…") }
        }
        .accessibilityElement(children: .contain)
    }

    private var supportsExtensionRecovery: Bool {
        #if HONBAKO_EXTERNAL_SOURCES
        true
        #else
        false
        #endif
    }

    private var packageHost: String {
        item.record?.repositoryURL.flatMap { URL(string: $0)?.host }
            ?? item.record?.packageURL.flatMap { URL(string: $0)?.host } ?? "Original extension"
    }
}
#endif
