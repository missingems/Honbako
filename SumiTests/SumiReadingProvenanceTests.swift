@testable import Sumi
import CoreData
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct SumiReadingProvenanceTests {
    @Test("Resume labels identify the recording device without inventing a device for legacy history")
    func recordingDeviceLabels() {
        #expect(SumiReadingProvenance.deviceLabel(id: "local", name: "iPad mini", currentID: "local") == "This device")
        #expect(SumiReadingProvenance.deviceLabel(id: "remote", name: "  iPhone Duo \n", currentID: "local") == "iPhone Duo")
        #expect(SumiReadingProvenance.deviceLabel(id: nil, name: nil, currentID: "local") == nil)
        #expect(SumiReadingProvenance.deviceLabel(id: "", name: "iPad mini", currentID: "local") == nil)
        #expect(SumiReadingProvenance.deviceLabel(id: "remote", name: " \n", currentID: "local") == nil)
        #expect(SumiReadingProvenance.deviceLabel(id: "remote", name: "iPad mini", currentID: nil) == "iPad mini")
    }

    @Test("The selected model puts optional device provenance on cloud-synced History")
    func optionalCloudAttributes() throws {
        let model = try versionedModel("0.11")
        let directory = try modelDirectory()
        let selected = try #require(NSManagedObjectModel(contentsOf: directory))
        let history = try #require(model.entitiesByName["History"])
        #expect(selected.entitiesByName["History"]?.versionHash == history.versionHash)
        #expect(model.entities(forConfigurationName: "Cloud")?.contains { $0.name == "History" } == true)
        #expect(model.entities(forConfigurationName: "Local")?.contains { $0.name == "History" } == false)
        for name in ["readDeviceID", "readDeviceName"] {
            let attribute = try #require(history.attributesByName[name])
            #expect(attribute.isOptional)
            #expect(attribute.attributeType == .stringAttributeType)
            #expect(!attribute.isTransient)
        }
    }

    @Test("A real 0.9 SQLite bookmark migrates without losing its chapter, page, date, or library link")
    func lightweightSQLiteMigrationPreservesBookmark() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sumi-provenance-migration-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("History.sqlite")
        let legacy = try versionedModel("0.9")
        let current = try versionedModel("0.11")
        #expect(legacy.entitiesByName["History"]?.attributesByName["readDeviceID"] == nil)
        let readAt = Date(timeIntervalSince1970: 1_791_234_567.25)
        try writeLegacyBookmark(to: url, model: legacy, date: readAt)
        let before = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: url)
        #expect(legacy.isConfiguration(withName: "Cloud", compatibleWithStoreMetadata: before))
        #expect(!current.isConfiguration(withName: "Cloud", compatibleWithStoreMetadata: before))

        let store = try SQLiteStore(model: current, url: url, migrate: true)
        defer { store.close() }
        let records = try store.context.fetch(HistoryObject.fetchRequest())
        let history = try #require(records.first)
        #expect(records.count == 1)
        #expect(history.sourceId == "migration-source")
        #expect(history.mangaId == "saved-manga")
        #expect(history.chapterId == "chapter-42-ja")
        #expect(history.progress == 17)
        #expect(history.total == 38)
        #expect(history.scrollPosition?.doubleValue == 0.375)
        #expect(!history.completed)
        #expect(history.dateRead == readAt)
        #expect(history.chapter?.id == "chapter-42-ja")
        #expect(history.chapter?.lang == "ja")
        #expect(history.chapter?.manga?.id == "saved-manga")
        #expect(history.chapter?.manga?.libraryObject != nil)
        #expect(history.readDeviceID == nil)
        #expect(history.readDeviceName == nil)
        #expect(SumiReadingProvenance.deviceLabel(for: history) == nil)
        let after = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: url)
        #expect(current.isConfiguration(withName: "Cloud", compatibleWithStoreMetadata: after))
    }

    @Test("The latest reread carries its device with its exact earlier page regardless of duplicate survivor", arguments: [true, false])
    func latestDeviceTravelsWithReread(keepOlderRecord: Bool) throws {
        try withCurrentStore { store in
            let older = try history(in: store.context, progress: 29, completed: true, date: 100,
                                    deviceID: "ipad", deviceName: "iPad mini")
            let later = try history(in: store.context, progress: 3, completed: false, date: 200,
                                    deviceID: "duo", deviceName: "iPhone Duo")
            later.total = 42
            later.scrollPosition = 0.175
            try store.context.save()
            let olderID = older.objectID
            CloudDataDeduplicator.deduplicate(objectID: olderID, context: store.context) { objectID in
                (objectID == olderID) == keepOlderRecord ? "a" : "b"
            }
            try store.context.save()
            let all = try store.context.fetch(HistoryObject.fetchRequest())
            let bookmark = try #require(all.first)
            #expect(all.count == 1)
            #expect(bookmark.progress == 3, "A later reread of an earlier page is the authoritative bookmark")
            #expect(bookmark.total == 42)
            #expect(bookmark.scrollPosition?.doubleValue == 0.175)
            #expect(!bookmark.completed)
            #expect(bookmark.dateRead == Date(timeIntervalSince1970: 200))
            #expect(bookmark.readDeviceID == "duo")
            #expect(bookmark.readDeviceName == "iPhone Duo")
            #expect((bookmark.objectID == olderID) == keepOlderRecord)
        }
    }

    @Test("Newer history with unknown provenance cannot inherit a stale device from an older duplicate")
    func latestUnknownDeviceRemainsUnknown() throws {
        try withCurrentStore { store in
            let older = try history(in: store.context, progress: 15, completed: false, date: 100,
                                    deviceID: "ipad", deviceName: "iPad mini")
            _ = try history(in: store.context, progress: 7, completed: false, date: 200,
                            deviceID: nil, deviceName: nil)
            try store.context.save()
            let olderID = older.objectID
            CloudDataDeduplicator.deduplicate(objectID: olderID, context: store.context) { $0 == olderID ? "a" : "b" }
            try store.context.save()
            let bookmark = try #require(store.context.fetch(HistoryObject.fetchRequest()).first)
            #expect(bookmark.progress == 7)
            #expect(bookmark.readDeviceID == nil)
            #expect(bookmark.readDeviceName == nil)
            #expect(SumiReadingProvenance.deviceLabel(for: bookmark) == nil)
        }
    }

    private func modelDirectory() throws -> URL {
        try #require(Bundle(for: CoreDataManager.self).url(forResource: "Aidoku", withExtension: "momd"))
    }

    private func versionedModel(_ version: String) throws -> NSManagedObjectModel {
        let url = try modelDirectory().appendingPathComponent("\(version).mom")
        return try #require(NSManagedObjectModel(contentsOf: url))
    }

    private func writeLegacyBookmark(to url: URL, model: NSManagedObjectModel, date: Date) throws {
        let store = try SQLiteStore(model: model, url: url)
        defer { store.close() }
        let context = store.context
        let manga = NSEntityDescription.insertNewObject(forEntityName: "Manga", into: context)
        manga.setValue("migration-source", forKey: "sourceId")
        manga.setValue("saved-manga", forKey: "id")
        manga.setValue("Saved Book", forKey: "title")
        let library = NSEntityDescription.insertNewObject(forEntityName: "LibraryManga", into: context)
        library.setValue(manga, forKey: "manga")
        let chapter = NSEntityDescription.insertNewObject(forEntityName: "Chapter", into: context)
        chapter.setValue("migration-source", forKey: "sourceId")
        chapter.setValue("saved-manga", forKey: "mangaId")
        chapter.setValue("chapter-42-ja", forKey: "id")
        chapter.setValue("ja", forKey: "lang")
        chapter.setValue(manga, forKey: "manga")
        let history = NSEntityDescription.insertNewObject(forEntityName: "History", into: context)
        history.setValue("migration-source", forKey: "sourceId")
        history.setValue("saved-manga", forKey: "mangaId")
        history.setValue("chapter-42-ja", forKey: "chapterId")
        history.setValue(17, forKey: "progress")
        history.setValue(38, forKey: "total")
        history.setValue(0.375, forKey: "scrollPosition")
        history.setValue(false, forKey: "completed")
        history.setValue(date, forKey: "dateRead")
        history.setValue(chapter, forKey: "chapter")
        try context.save()
    }

    private func history(in context: NSManagedObjectContext, progress: Int16, completed: Bool,
                         date: TimeInterval, deviceID: String?, deviceName: String?) throws -> HistoryObject {
        let record = try #require(NSEntityDescription.insertNewObject(forEntityName: "History", into: context) as? HistoryObject)
        record.sourceId = "merge-source"
        record.mangaId = "same-manga"
        record.chapterId = "same-chapter"
        record.progress = progress
        record.total = 40
        record.completed = completed
        record.dateRead = Date(timeIntervalSince1970: date)
        record.readDeviceID = deviceID
        record.readDeviceName = deviceName
        return record
    }

    private func withCurrentStore(_ operation: (SQLiteStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sumi-provenance-merge-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteStore(model: versionedModel("0.11"), url: directory.appendingPathComponent("History.sqlite"))
        defer { store.close() }
        try operation(store)
    }

    private struct SQLiteStore {
        let coordinator: NSPersistentStoreCoordinator
        let store: NSPersistentStore
        let context: NSManagedObjectContext

        init(model: NSManagedObjectModel, url: URL, migrate: Bool = false) throws {
            coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: "Cloud", at: url,
                options: migrate ? [NSMigratePersistentStoresAutomaticallyOption: true,
                                    NSInferMappingModelAutomaticallyOption: true] : nil)
            context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
        }

        func close() {
            context.reset()
            try? coordinator.remove(store)
        }
    }
}
