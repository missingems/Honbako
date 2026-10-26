import CloudKit
import Combine
import CoreData
import UIKit

/// Reports account and mirroring events; it never claims that a manual account
/// check forces CloudKit to upload or download immediately.
@MainActor
final class CloudSyncStatus: ObservableObject {
    static let shared = CloudSyncStatus()

    @Published private(set) var accountStatus: CKAccountStatus?
    @Published private(set) var checkingAccount = false
    @Published private(set) var enabledAtLaunch = false
    @Published private(set) var activeEvents: Set<UUID> = []
    @Published private var accountError: String?
    @Published private var storeError: String?
    @Published private var syncErrors: [Int: String] = [:]
    var lastError: String? { storeError ?? accountError ?? syncErrors.sorted { $0.key < $1.key }.first?.value }
    @Published private(set) var lastUpload: Date?
    @Published private(set) var lastDownload: Date?

    private var started = false
    private var cancellables: Set<AnyCancellable> = []
    private let uploadKey = "Flag.iCloud.lastUpload"
    private let downloadKey = "Flag.iCloud.lastDownload"

    private init() {
        lastUpload = UserDefaults.standard.object(forKey: uploadKey) as? Date
        lastDownload = UserDefaults.standard.object(forKey: downloadKey) as? Date
    }

    var configured: Bool { CoreDataManager.containerID != nil }

    func start() {
        guard !started else { return }
        started = true
        enabledAtLaunch = CoreDataManager.shared.isCloudSyncEnabled
        writeDiagnostics()
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .sink { [weak self] notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
                Task { @MainActor in self?.record(event) }
            }
            .store(in: &cancellables)
        Publishers.Merge(
            NotificationCenter.default.publisher(for: .CKAccountChanged),
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        )
        .sink { [weak self] _ in
            Task { @MainActor in await self?.refreshAccount() }
        }
        .store(in: &cancellables)
        Task { await refreshAccount() }
    }

    func preferencesChanged() {
        objectWillChange.send()
        writeDiagnostics()
    }

    func refreshAccount() async {
        guard !checkingAccount else { return }
        guard let identifier = CoreDataManager.containerID else {
            AppSettings.flags.isiCloudAvailable.set(false)
            accountError = NSLocalizedString("ICLOUD_SYNC_CONFIGURATION_ERROR")
            writeDiagnostics()
            return
        }
        checkingAccount = true
        writeDiagnostics()
        defer {
            checkingAccount = false
            writeDiagnostics()
        }
        do {
            let status = try await CKContainer(identifier: identifier).accountStatus()
            accountStatus = status
            accountError = nil
            AppSettings.flags.isiCloudAvailable.set(status == .available)
        } catch {
            accountStatus = .couldNotDetermine
            AppSettings.flags.isiCloudAvailable.set(false)
            accountError = Self.message(for: error)
        }
    }

    func recordStoreError(_ error: Error) {
        storeError = error.localizedDescription
        writeDiagnostics()
    }

    private func record(_ event: NSPersistentCloudKitContainer.Event) {
        defer { writeDiagnostics() }
        if event.endDate == nil {
            activeEvents.insert(event.identifier)
            return
        }
        activeEvents.remove(event.identifier)
        if let error = event.error {
            syncErrors[event.type.rawValue] = Self.message(for: error)
            return
        }
        guard event.succeeded else { return }
        syncErrors[event.type.rawValue] = nil
        switch event.type {
            case .export:
                lastUpload = event.endDate
                UserDefaults.standard.set(event.endDate, forKey: uploadKey)
            case .import:
                lastDownload = event.endDate
                UserDefaults.standard.set(event.endDate, forKey: downloadKey)
            case .setup:
                break
            @unknown default:
                break
        }
    }

    private func writeDiagnostics() {
#if DEBUG
        let account: String
        switch accountStatus {
            case .available: account = "available"
            case .noAccount: account = "noAccount"
            case .restricted: account = "restricted"
            case .temporarilyUnavailable: account = "temporarilyUnavailable"
            case .couldNotDetermine: account = "couldNotDetermine"
            case .none: account = "notChecked"
            @unknown default: account = "unknown"
        }
        CloudSyncDiagnostics.write(
            enabledAtLaunch: enabledAtLaunch,
            configured: configured,
            accountStatus: account,
            checkingAccount: checkingAccount,
            activeEventCount: activeEvents.count,
            lastUpload: lastUpload,
            lastDownload: lastDownload,
            lastError: lastError
        )
#endif
    }

    private static func message(for error: Error) -> String {
        guard let cloudError = error as? CKError else { return error.localizedDescription }
        let key: String
        switch cloudError.code {
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                key = "ICLOUD_SYNC_WAITING_NETWORK"
            case .quotaExceeded:
                key = "ICLOUD_SYNC_STORAGE_FULL"
            case .notAuthenticated:
                key = "ICLOUD_SYNC_NO_ACCOUNT"
            case .badContainer, .missingEntitlement, .permissionFailure:
                key = "ICLOUD_SYNC_CONFIGURATION_ERROR"
            default:
                key = "ICLOUD_SYNC_FAILED"
        }
        return NSLocalizedString(key)
    }
}
