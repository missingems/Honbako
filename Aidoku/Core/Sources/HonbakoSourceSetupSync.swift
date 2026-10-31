#if SUMI
import CloudKit
import Foundation
import Observation
import UIKit

/// Syncs setup metadata independently of the local-only Source entity and package binaries.
@MainActor @Observable
final class HonbakoSourceSetupSync {
    static let shared: HonbakoSourceSetupSync = {
        let process = ProcessInfo.processInfo
        let allowed = HonbakoSourceSetupPolicy.permitsLiveStore(arguments: process.arguments, environment: process.environment)
        return HonbakoSourceSetupSync(store: allowed ? HonbakoUbiquitousSourceSetupStore() : nil,
            enabled: { CoreDataManager.containerID != nil && CoreDataManager.shared.isCloudSyncEnabled && AppSettings.general.icloudSync.get() },
            accountAvailable: {
                guard let id = CoreDataManager.containerID else { return false }
                return (try? await CKContainer(identifier: id).accountStatus()) == .available
            },
            localRecords: { await SourceManager.shared.sourceSetupRecords() },
            restoreConnections: { await SourceManager.shared.restoreSourceSetupConnections($0) },
            missingLibraryIDs: { await SourceManager.shared.sourceSetupMissingLibraryIDs() },
            restorePackage: { await SourceManager.shared.restoreSourceSetupPackage($0) })
    }()

    private(set) var missing: [HonbakoSourceSetupRecovery] = []
    private(set) var personalServers: [HonbakoSourceSetupRecord] = []
    private(set) var isChecking = false
    private(set) var restoringID: String?
    private(set) var lastError: String?
    private(set) var backupCount = 0
    private(set) var cloudAvailable = false

    @ObservationIgnored private let store: (any HonbakoSourceSetupCloudStore)?
    @ObservationIgnored private let enabled: () -> Bool
    @ObservationIgnored private let accountAvailable: () async -> Bool
    @ObservationIgnored private let localRecords: () async -> [HonbakoSourceSetupRecord]
    @ObservationIgnored private let restoreConnections: ([HonbakoSourceSetupRecord]) async -> Void
    @ObservationIgnored private let missingLibraryIDs: () async -> [String]
    @ObservationIgnored private let restorePackage: (HonbakoSourceSetupRecord) async -> Bool
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var localSnapshot: [String: HonbakoSourceSetupRecord]?
    @ObservationIgnored private var retryKeys: Set<String> = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var refreshPending = false

    init(store: (any HonbakoSourceSetupCloudStore)?, enabled: @escaping () -> Bool,
         accountAvailable: @escaping () async -> Bool,
         localRecords: @escaping () async -> [HonbakoSourceSetupRecord],
         restoreConnections: @escaping ([HonbakoSourceSetupRecord]) async -> Void,
         missingLibraryIDs: @escaping () async -> [String],
         restorePackage: @escaping (HonbakoSourceSetupRecord) async -> Bool) {
        self.store = store; self.enabled = enabled; self.accountAvailable = accountAvailable
        self.localRecords = localRecords; self.restoreConnections = restoreConnections
        self.missingLibraryIDs = missingLibraryIDs; self.restorePackage = restorePackage
    }

    func start() {
        guard !started, store != nil else { return }
        started = true
        let names: [Notification.Name] = [.sourceLoaded, .sourceUnloaded, .updateSourceList, .updateSourceLists,
            .updateLibrary, .init("Honbako.SourceSetup.Changed"), .init(AppSettings.general.icloudSync.key),
            .CKAccountChanged, UIApplication.didBecomeActiveNotification,
            NSUbiquitousKeyValueStore.didChangeExternallyNotification, .init("Honbako.SourceSetup.Removed")]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let sourceID = note.userInfo?["sourceID"] as? String
                let repositoryURL = note.userInfo?["repositoryURL"] as? String
                let quota = (note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int) == NSUbiquitousKeyValueStoreQuotaViolationChange
                Task { @MainActor in
                    guard let self else { return }
                    if let id = sourceID ?? repositoryURL {
                        await self.recordRemoval(id: id, repository: repositoryURL != nil)
                        return
                    }
                    if quota { self.lastError = String(localized: "iCloud has no room for additional connection details."); return }
                    await self.refresh()
                }
            })
        }
        Task { await refresh() }
    }

    /// Empty local state publishes no aggregate or deletion. Initial local conflicts stay local.
    func refresh() async {
        guard let store else { return }
        guard !isChecking else { refreshPending = true; return }
        isChecking = true
        defer {
            isChecking = false
            if refreshPending { refreshPending = false; Task { await refresh() } }
        }
        guard enabled() else {
            cloudAvailable = false; localSnapshot = nil; missing = []; personalServers = []
            return
        }
        let missingIDs = await missingLibraryIDs()
        guard await accountAvailable(), enabled() else {
            cloudAvailable = false
            missing = missingIDs.map { .init(id: $0, record: nil) }
            return
        }
        cloudAvailable = true
        store.synchronize()
        var cloud = cloudRecords(store)
        let active = cloud.values.filter { !$0.removed }
        await restoreConnections(Array(active))
        guard enabled() else { return }
        let local = await localRecords().filter { HonbakoSourceSetupPolicy.validate($0) && !$0.removed }
        guard enabled() else { return }
        let current = Dictionary(local.map { (HonbakoSourceSetupPolicy.key(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        for (key, record) in current {
            let changed = localSnapshot?[key].map { !HonbakoSourceSetupPolicy.sameSetup($0, record) } ?? false
            if cloud[key] == nil || changed || retryKeys.contains(key) {
                if write(record, key: key, store: store, cloud: &cloud) { retryKeys.remove(key) }
                else { retryKeys.insert(key) }
            }
        }
        localSnapshot = current
        backupCount = cloud.values.filter { !$0.removed && $0.kind != .repository }.count
        let installedIDs = Set(local.filter { $0.kind != .repository }.map(\.id))
        let savedSources = Dictionary(cloud.values.filter { $0.kind != .repository && !$0.removed }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var pending = Dictionary(missingIDs.map { ($0, HonbakoSourceSetupRecovery(id: $0, record: savedSources[$0])) }, uniquingKeysWith: { first, _ in first })
        for record in cloud.values where !record.removed && record.kind != .repository && !installedIDs.contains(record.id) {
            pending[record.id] = .init(id: record.id, record: record)
        }
        // Re-read after bundled connections have been restored; a Source row alone does not prove a package loads.
        let stillMissing = Set(await missingLibraryIDs())
        pending = pending.filter { !installedIDs.contains($0.key) || stillMissing.contains($0.key) }
        missing = pending.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        personalServers = local.filter { [.komga, .kavita, .suwayomi].contains($0.kind) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        store.synchronize()
    }

    /// Only an explicit local remove action creates a tombstone. An empty or temporarily
    /// unreadable source database is never evidence that the user deleted their setup.
    func recordRemoval(id: String, repository: Bool) async {
        guard let store, enabled(), await accountAvailable(), enabled() else { return }
        // A quick remove/re-add may complete while account verification is awaiting.
        let local = await localRecords()
        guard !local.contains(where: { $0.id == id && ($0.kind == .repository) == repository }), enabled() else { return }
        let template = HonbakoSourceSetupRecord(id: id, kind: repository ? .repository : .extensionPackage, name: id)
        let key = HonbakoSourceSetupPolicy.key(for: template)
        var cloud = cloudRecords(store)
        guard var record = cloud[key] else { return }
        record.removed = true
        _ = write(record, key: key, store: store, cloud: &cloud)
        localSnapshot?.removeValue(forKey: key)
        store.synchronize()
    }

    func restore(_ recovery: HonbakoSourceSetupRecovery) async {
        guard enabled(), restoringID == nil else { return }
        if recovery.canReconnectBundledSource {
            restoringID = recovery.id
            defer { restoringID = nil }
            await restoreConnections([.init(id: "honbako.mangadex", kind: .mangaDex, name: "MangaDex", version: 1)])
            await refresh()
            return
        }
        guard cloudAvailable, recovery.canRestorePackage, let record = recovery.record else { return }
        restoringID = recovery.id
        defer { restoringID = nil }
        if await restorePackage(record) { lastError = nil }
        else { lastError = String(localized: "This extension couldn’t be restored at its saved version. Add its original extension repository or import the extension file again.") }
        await refresh()
    }

    private func cloudRecords(_ store: any HonbakoSourceSetupCloudStore) -> [String: HonbakoSourceSetupRecord] {
        var result: [String: HonbakoSourceSetupRecord] = [:]
        var bytes = 0
        for key in store.keys.filter({ $0.hasPrefix(HonbakoSourceSetupPolicy.prefix) }).sorted().prefix(HonbakoSourceSetupPolicy.maxRecords) {
            guard let data = store.data(forKey: key) else { continue }
            bytes += data.count + key.utf8.count
            guard bytes <= HonbakoSourceSetupPolicy.maxTotalBytes else { lastError = String(localized: "Some connection details exceed iCloud’s backup limit."); break }
            if let record = HonbakoSourceSetupPolicy.decode(data, key: key) { result[key] = record }
        }
        return result
    }

    private func write(_ value: HonbakoSourceSetupRecord, key: String, store: any HonbakoSourceSetupCloudStore,
                       cloud: inout [String: HonbakoSourceSetupRecord]) -> Bool {
        if let saved = cloud[key], HonbakoSourceSetupPolicy.sameSetup(saved, value) { return true }
        var record = value
        record.updatedAt = .now
        guard let data = HonbakoSourceSetupPolicy.encode(record) else { return false }
        let keys = store.keys.filter { $0.hasPrefix(HonbakoSourceSetupPolicy.prefix) }
        let total = keys.reduce(0) { $0 + $1.utf8.count + (store.data(forKey: $1)?.count ?? 0) }
        let previous = store.data(forKey: key)?.count ?? 0
        guard keys.contains(key) || (keys.count < HonbakoSourceSetupPolicy.maxRecords && store.keys.count < 900),
              total - previous + data.count + (keys.contains(key) ? 0 : key.utf8.count) <= HonbakoSourceSetupPolicy.maxTotalBytes else {
            lastError = String(localized: "iCloud has no room for additional connection details.")
            return false
        }
        store.set(data, forKey: key)
        cloud[key] = record
        return true
    }
}
#endif
