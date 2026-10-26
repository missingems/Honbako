//
//  CoreDataManager.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/2/22.
//

import Combine
import CoreData

final class CoreDataManager: @unchecked Sendable {
    static let shared = CoreDataManager()

    static let containerID = CloudSyncConfiguration.containerIdentifier(info: Bundle.main.infoDictionary ?? [:])

    let container: NSPersistentCloudKitContainer

    @MainActor
    var context: NSManagedObjectContext {
        container.viewContext
    }

    // only accessed from init
    private var cancellables: Set<AnyCancellable> = []

    private let remoteHistoryQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.aidoku.remote-history"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    // only accessed from remoteHistoryQueue
    private var lastHistoryToken: NSPersistentHistoryToken?
    private var didLoadHistoryToken = false
    private let usesCloudKitMirroring: Bool
    var isCloudSyncEnabled: Bool { usesCloudKitMirroring }

    private static let historyTokenUrl = FileManager.default.applicationSupportDirectory
        .appendingPathComponent("historyToken.data")

    private static var shouldUseiCloud: Bool {
        // Configure the store before loading it. CloudKit itself handles account
        // sign-in and connectivity changes without depending on iCloud Drive.
        AppSettings.general.icloudSync.get() && containerID != nil
    }

    private init() {
        let usesCloudKitMirroring = Self.shouldUseiCloud
        self.usesCloudKitMirroring = usesCloudKitMirroring
        self.container = Self.createContainer(usesCloudKitMirroring: usesCloudKitMirroring)

        NotificationCenter.default.publisher(
            for: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
        .sink { [weak self] _ in
            self?.storeRemoteChange()
        }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .init(AppSettings.general.icloudSync.key))
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateCloudConfiguration()
                }
            }
            .store(in: &cancellables)
    }

    static func createContainer(usesCloudKitMirroring: Bool) -> NSPersistentCloudKitContainer {
        let container = NSPersistentCloudKitContainer(name: "Aidoku")

        let storeDirectory = FileManager.default.applicationSupportDirectory

        let cloudDescription = NSPersistentStoreDescription(url: storeDirectory.appendingPathComponent("Aidoku.sqlite"))
        cloudDescription.configuration = "Cloud"
        cloudDescription.shouldMigrateStoreAutomatically = true
        cloudDescription.shouldInferMappingModelAutomatically = true

        cloudDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        cloudDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        let localDescription = NSPersistentStoreDescription(url: storeDirectory.appendingPathComponent("Local.sqlite"))
        localDescription.configuration = "Local"
        localDescription.shouldMigrateStoreAutomatically = true
        localDescription.shouldInferMappingModelAutomatically = true

        if usesCloudKitMirroring, let containerID {
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
            options.databaseScope = .private
            cloudDescription.cloudKitContainerOptions = options
        } else {
            cloudDescription.cloudKitContainerOptions = nil
        }

        container.persistentStoreDescriptions = [
            cloudDescription,
            localDescription
        ]

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                LogManager.logger.error("Error loading persistent stores \(error), \(error.userInfo)")
                Task { @MainActor in CloudSyncStatus.shared.recordStoreError(error) }
            }
        }

//        do {
//            try container.initializeCloudKitSchema(options: [.printSchema])
//        } catch {
//            print("error initializing cloudkit schema:", error)
//        }

        return container
    }

    @MainActor
    func save() {
        do {
            try context.save()
        } catch {
            LogManager.logger.error("CoreDataManager.save: \(error.localizedDescription)")
        }
    }

//    func saveIfNeeded() {
//        if context.hasChanges {
//            save()
//        }
//    }

    func remove(_ objectID: NSManagedObjectID) {
        container.performBackgroundTask { context in
            let object = context.object(with: objectID)
            context.delete(object)
            try? context.save()
        }
    }

    /// Clear all objects from fetch request.
    func clear<T: NSManagedObject>(request: NSFetchRequest<T>, context: NSManagedObjectContext) {
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: (request as? NSFetchRequest<NSFetchRequestResult>)!)
        do {
            _ = try context.execute(deleteRequest)
        } catch {
            LogManager.logger.error("CoreDataManager.clear: \(error.localizedDescription)")
        }
    }

    func queueClear<T: NSManagedObject>(request: NSFetchRequest<T>, context: NSManagedObjectContext) {
        let objects = (try? context.fetch(request)) ?? []
        for object in objects {
            context.delete(object)
        }
    }

    @MainActor
    func updateCloudConfiguration() {
        // Changing a description after its store is loaded does not reconfigure
        // CloudKit. Apply this preference at the next launch and tell the user;
        // unloading a live store would invalidate readers and background tasks.
        CloudSyncStatus.shared.preferencesChanged()
    }

    // TODO: clean this up
    func migrateChapterHistory(progress: (@Sendable (Float) -> Void)? = nil) async {
        LogManager.logger.info("Beginning chapter history migration for 0.6")

        await container.performBackgroundTask { context in
            let request = HistoryObject.fetchRequest()
            let historyObjects = (try? context.fetch(request)) ?? []
            let total = Float(historyObjects.count)
            var i: Float = 0
            var count = 0
            for historyObject in historyObjects {
                progress?(i / total)
                i += 1
                guard
                    historyObject.chapter == nil,
                    let chapterObject = self.getChapter(
                        chapterId: historyObject.identifier,
                        context: context
                    )
                else { continue }
                historyObject.chapter = chapterObject
                count += 1
            }
            try? context.save()

            LogManager.logger.info("Migrated \(count)/\(historyObjects.count) history objects")
        }
    }
}

extension CoreDataManager {
    func storeRemoteChange() {
        remoteHistoryQueue.addOperation { [weak self] in
            guard let self else { return }
            guard self.usesCloudKitMirroring else { return }
            let context = self.container.newBackgroundContext()
            context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
            context.performAndWait {
                let historyFetchRequest = NSPersistentHistoryTransaction.fetchRequest!
                let request: NSPersistentHistoryChangeRequest
                if let token = self.historyToken() {
                    request = .fetchHistory(after: token)
                } else {
                    request = .fetchHistory(after: nil as NSPersistentHistoryToken?)
                }
                request.fetchRequest = historyFetchRequest
                let cloudStores = self.container.persistentStoreCoordinator.persistentStores.filter { $0.configurationName == "Cloud" }
                request.affectedStores = cloudStores

                var result = (try? context.execute(request)) as? NSPersistentHistoryResult
                if result == nil && self.historyToken() != nil {
                    self.clearHistoryToken()
                    let fallback = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
                    fallback.fetchRequest = historyFetchRequest
                    fallback.affectedStores = cloudStores
                    result = (try? context.execute(fallback)) as? NSPersistentHistoryResult
                }
                guard
                    let transactions = result?.result as? [NSPersistentHistoryTransaction],
                    !transactions.isEmpty
                else { return }

                var newObjectIds = [NSManagedObjectID]()
                var importedChanges: [[AnyHashable: Any]] = []
                var shouldUpdateLibrary = false
                var shouldUpdateHistory = false
                let entityNames = [
                    CategoryObject.entity().name,
                    ChapterObject.entity().name,
                    HistoryObject.entity().name,
                    LibraryMangaObject.entity().name,
                    MangaObject.entity().name,
                    TrackObject.entity().name
                ]

                for
                    transaction in transactions
                    where transaction.changes != nil && transaction.author == "NSCloudKitMirroringDelegate.import"
                {
                    if let changes = transaction.objectIDNotification().userInfo {
                        importedChanges.append(changes)
                    }
                    for
                        change in transaction.changes!
                        where entityNames.contains(change.changedObjectID.entity.name)
                    {
                        shouldUpdateLibrary = true
                        if change.changedObjectID.entity.name == HistoryObject.entity().name {
                            shouldUpdateHistory = true
                        }
                        if change.changeType == .insert {
                            newObjectIds.append(change.changedObjectID)
                        }
                    }
                }

                if !newObjectIds.isEmpty {
                    self.deduplicate(objectIds: newObjectIds)
                }

                self.setHistoryToken(transactions.last!.token)

                if shouldUpdateLibrary {
                    Task { @MainActor [shouldUpdateHistory, importedChanges] in
                        for changes in importedChanges {
                            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.container.viewContext])
                        }
                        NotificationCenter.default.post(name: .updateLibrary, object: nil)
                        if shouldUpdateHistory {
                            NotificationCenter.default.post(name: .updateHistory, object: nil)
                        }
                    }
                }
            }
        }
    }

    // Do not manually prune the Cloud-configured store history, even while sync is off.
    // The mirroring delegate may still need changes made before its last export.

    private func historyToken() -> NSPersistentHistoryToken? {
        if !didLoadHistoryToken {
            didLoadHistoryToken = true
            if let data = try? Data(contentsOf: Self.historyTokenUrl) {
                lastHistoryToken = try? NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NSPersistentHistoryToken.self,
                    from: data
                )
            }
        }
        return lastHistoryToken
    }

    private func clearHistoryToken() {
        didLoadHistoryToken = true
        lastHistoryToken = nil
        Self.historyTokenUrl.removeItem()
    }

    private func setHistoryToken(_ token: NSPersistentHistoryToken) {
        didLoadHistoryToken = true
        lastHistoryToken = token
        guard
            let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        else { return }
        try? data.write(to: Self.historyTokenUrl, options: .atomic)
    }

    func deduplicate(objectIds: [NSManagedObjectID]) {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        // Work in batches, saving and resetting in between.
        for batch in objectIds.chunked(into: 500) {
            context.performAndWait {
                for objectId in batch {
                    deduplicate(objectId: objectId, context: context)
                }
                do {
                    try context.save()
                } catch {
                    LogManager.logger.error("deduplicate: \(error.localizedDescription)")
                }
                context.reset()
            }
        }
    }

    func deduplicate(objectId: NSManagedObjectID, context: NSManagedObjectContext) {
        CloudDataDeduplicator.deduplicate(objectID: objectId, context: context) { objectID in
            self.container.recordID(for: objectID)?.recordName ?? objectID.uriRepresentation().absoluteString
        }
    }
}
