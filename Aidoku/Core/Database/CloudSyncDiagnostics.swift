#if DEBUG
import Foundation

/// A deliberately small diagnostic report for an explicitly flagged debug launch.
/// No other preferences, library contents, or credentials are inspected.
@MainActor
enum CloudSyncDiagnostics {
    private struct Report: Encodable {
        let generatedAt: Date
        let processID: Int32
        let preferences: [String: Bool]
        let paperTextureStrength: String
        let pageSizing: String
        let enabledAtLaunch: Bool
        let configured: Bool
        let accountStatus: String
        let checkingAccount: Bool
        let activeEventCount: Int
        let lastUpload: Date?
        let lastDownload: Date?
        let lastError: String?
    }

    static func write(
        enabledAtLaunch: Bool,
        configured: Bool,
        accountStatus: String,
        checkingAccount: Bool,
        activeEventCount: Int,
        lastUpload: Date?,
        lastDownload: Date?,
        lastError: String?
    ) {
        guard ProcessInfo.processInfo.arguments.contains("--aidoku-sync-diagnostics") else { return }
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let report = Report(
            generatedAt: Date(),
            processID: ProcessInfo.processInfo.processIdentifier,
            preferences: [
                "Reader.paperTexture": AppSettings.reader.paperTexture.get(),
                "Library.notifyNewChapters": AppSettings.library.notifyNewChapters.get(),
                "General.icloudSync": AppSettings.general.icloudSync.get()
            ],
            paperTextureStrength: AppSettings.reader.paperTextureStrength.get().rawValue,
            pageSizing: AppSettings.reader.pageSizing.get().rawValue,
            enabledAtLaunch: enabledAtLaunch,
            configured: configured,
            accountStatus: accountStatus,
            checkingAccount: checkingAccount,
            activeEventCount: activeEventCount,
            lastUpload: lastUpload,
            lastDownload: lastDownload,
            lastError: lastError.map { String($0.prefix(2048)) }
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            try data.write(to: caches.appendingPathComponent("AidokuSyncDiagnostics.json"), options: .atomic)
        } catch {
            LogManager.logger.error("Could not write scoped sync diagnostics: \(error.localizedDescription)")
        }
    }
}
#endif
