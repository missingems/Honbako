@testable import Aidoku
import CoreData
import Testing

struct CloudSyncConfigurationTests {
    @Test func requiresResolvedOwnContainerIdentifier() {
        #expect(CloudSyncConfiguration.containerIdentifier(info: ["ICLOUD_CONTAINER_ID": "iCloud.dev.jun.Aidoku"]) == "iCloud.dev.jun.Aidoku")
        #expect(CloudSyncConfiguration.containerIdentifier(info: [:]) == nil)
        #expect(CloudSyncConfiguration.containerIdentifier(info: ["ICLOUD_CONTAINER_ID": "$(ICLOUD_CONTAINER_ID)"]) == nil)
        #expect(CloudSyncConfiguration.containerIdentifier(info: ["ICLOUD_CONTAINER_ID": ""]) == nil)
    }
}

@MainActor
struct CloudDataDeduplicatorTests {
    @Test func newestRereadWinsAndReadingSessionsSurvive() throws {
        let context = try makeContext()
        let earlier = history(context, progress: 20, completed: true, date: 100)
        let latest = history(context, progress: 3, completed: false, date: 200)
        let firstSession = ReadingSessionObject(context: context)
        firstSession.history = earlier
        let secondSession = ReadingSessionObject(context: context)
        secondSession.history = latest
        try context.save()

        CloudDataDeduplicator.deduplicate(objectID: earlier.objectID, context: context)
        try context.save()

        let records = try context.fetch(HistoryObject.fetchRequest())
        let survivor = try #require(records.first)
        #expect(records.count == 1)
        #expect(survivor.progress == 3)
        #expect(!survivor.completed)
        #expect(survivor.dateRead == Date(timeIntervalSince1970: 200))
        #expect(survivor.sessions?.count == 2)
        #expect(try context.count(for: ReadingSessionObject.fetchRequest()) == 2)
    }

    @Test func chapterMergeRetainsNewerProgressAndLinks() throws {
        let context = try makeContext()
        let first = chapter(context)
        let second = chapter(context)
        let oldHistory = history(context, progress: 8, completed: false, date: 100)
        let newHistory = history(context, progress: 12, completed: true, date: 200)
        first.history = oldHistory
        second.history = newHistory
        try context.save()

        CloudDataDeduplicator.deduplicate(objectID: first.objectID, context: context)
        try context.save()

        let records = try context.fetch(ChapterObject.fetchRequest())
        #expect(records.count == 1)
        #expect(records.first?.history?.progress == 12)
        #expect(records.first?.history?.completed == true)
        #expect(try context.count(for: HistoryObject.fetchRequest()) == 1)
    }

    @Test func mangaMergePreservesLibraryMembershipCategoriesAndChapters() throws {
        let context = try makeContext()
        let first = manga(context)
        let second = manga(context)
        let firstLibrary = LibraryMangaObject(context: context)
        let secondLibrary = LibraryMangaObject(context: context)
        first.libraryObject = firstLibrary
        second.libraryObject = secondLibrary
        firstLibrary.dateAdded = Date(timeIntervalSince1970: 100)
        secondLibrary.dateAdded = Date(timeIntervalSince1970: 200)
        let firstCategory = CategoryObject(context: context)
        firstCategory.title = "Favorites"
        let secondCategory = CategoryObject(context: context)
        secondCategory.title = "Reading"
        firstLibrary.addToCategories(firstCategory)
        secondLibrary.addToCategories(secondCategory)
        let firstChapter = chapter(context)
        firstChapter.id = "1"
        firstChapter.manga = first
        let secondChapter = chapter(context)
        secondChapter.id = "2"
        secondChapter.manga = second
        try context.save()

        CloudDataDeduplicator.deduplicate(objectID: first.objectID, context: context)
        try context.save()

        let records = try context.fetch(MangaObject.fetchRequest())
        let survivor = try #require(records.first)
        #expect(records.count == 1)
        #expect(survivor.chapters?.count == 2)
        #expect(survivor.libraryObject?.categories?.count == 2)
        #expect(survivor.libraryObject?.dateAdded == Date(timeIntervalSince1970: 100))
        #expect(try context.count(for: LibraryMangaObject.fetchRequest()) == 1)
    }

    @Test func categoryAndFilterGroupWithSameNameRemainDistinct() throws {
        let context = try makeContext()
        let category = CategoryObject(context: context)
        category.title = "Reading"
        category.group = false
        let group = CategoryObject(context: context)
        group.title = "Reading"
        group.group = true
        try context.save()

        CloudDataDeduplicator.deduplicate(objectID: category.objectID, context: context)
        try context.save()

        #expect(try context.count(for: CategoryObject.fetchRequest()) == 2)
    }

    @Test func parentAndChildMergeOrderChooseSameHistoryRecord() throws {
        for parentFirst in [true, false] {
            let context = try makeContext()
            let first = chapter(context)
            let second = chapter(context)
            let earlier = history(context, progress: 20, completed: true, date: 100)
            let later = history(context, progress: 2, completed: false, date: 200)
            first.history = earlier
            second.history = later
            try context.save()
            let canonicalHistoryID = later.objectID
            let keys = [first.objectID: "chapter-a", second.objectID: "chapter-b",
                        earlier.objectID: "history-b", later.objectID: "history-a"]
            let stableKey: (NSManagedObjectID) -> String = { keys[$0] ?? $0.uriRepresentation().absoluteString }
            let ids = parentFirst ? [first.objectID, earlier.objectID] : [earlier.objectID, first.objectID]
            for id in ids {
                CloudDataDeduplicator.deduplicate(objectID: id, context: context, stableKey: stableKey)
            }
            try context.save()

            let records = try context.fetch(HistoryObject.fetchRequest())
            #expect(records.count == 1)
            #expect(records.first?.objectID == canonicalHistoryID)
            #expect(records.first?.progress == 2)
            #expect(records.first?.completed == false)
            #expect(records.first?.chapter?.objectID == first.objectID)
        }
    }

    @Test func parentAndChildMergeOrderChooseSameLibraryRecord() throws {
        for parentFirst in [true, false] {
            let context = try makeContext()
            let first = manga(context)
            let second = manga(context)
            let firstLibrary = LibraryMangaObject(context: context)
            let secondLibrary = LibraryMangaObject(context: context)
            first.libraryObject = firstLibrary
            second.libraryObject = secondLibrary
            try context.save()
            let canonicalLibraryID = secondLibrary.objectID
            let keys = [first.objectID: "manga-a", second.objectID: "manga-b",
                        firstLibrary.objectID: "library-b", secondLibrary.objectID: "library-a"]
            let stableKey: (NSManagedObjectID) -> String = { keys[$0] ?? $0.uriRepresentation().absoluteString }
            let ids = parentFirst ? [first.objectID, firstLibrary.objectID] : [firstLibrary.objectID, first.objectID]
            for id in ids {
                CloudDataDeduplicator.deduplicate(objectID: id, context: context, stableKey: stableKey)
            }
            try context.save()

            let records = try context.fetch(LibraryMangaObject.fetchRequest())
            #expect(records.count == 1)
            #expect(records.first?.objectID == canonicalLibraryID)
            #expect(records.first?.manga?.objectID == first.objectID)
        }
    }

    @Test func complementaryMetadataEditsAndTheirFlagsSurvive() throws {
        let context = try makeContext()
        let first = manga(context)
        let second = manga(context)
        first.title = "My Title"
        first.editedKeys = EditedKeys.title.rawValue
        first.author = "Source Author"
        second.title = "Source Title"
        second.author = nil
        second.cover = "my-cover"
        second.editedKeys = EditedKeys.authors.union(.cover).rawValue
        try context.save()
        let firstID = first.objectID
        CloudDataDeduplicator.deduplicate(objectID: firstID, context: context) {
            $0 == firstID ? "a" : "b"
        }
        try context.save()

        let survivor = try #require(context.fetch(MangaObject.fetchRequest()).first)
        #expect(survivor.title == "My Title")
        #expect(survivor.author == nil)
        #expect(survivor.cover == "my-cover")
        #expect(EditedKeys(rawValue: survivor.editedKeys) == [.title, .authors, .cover])
    }

    private func makeContext() throws -> NSManagedObjectContext {
        let model = try #require(NSManagedObjectModel.mergedModel(from: [Bundle(for: CoreDataManager.self)]))
        let testModel = model.copy() as! NSManagedObjectModel
        // In-memory stores do not support SQL-derived attributes. No merge path
        // uses chapterCount; removing only that derived cache keeps real entities.
        for entity in testModel.entities {
            entity.properties = entity.properties.filter { !($0 is NSDerivedAttributeDescription) }
        }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: testModel)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    private func history(_ context: NSManagedObjectContext, progress: Int16, completed: Bool, date: TimeInterval) -> HistoryObject {
        let record = HistoryObject(context: context)
        record.sourceId = "test"
        record.mangaId = "manga"
        record.chapterId = "1"
        record.progress = progress
        record.completed = completed
        record.dateRead = Date(timeIntervalSince1970: date)
        return record
    }

    private func chapter(_ context: NSManagedObjectContext) -> ChapterObject {
        let record = ChapterObject(context: context)
        record.sourceId = "test"
        record.mangaId = "manga"
        record.id = "1"
        return record
    }

    private func manga(_ context: NSManagedObjectContext) -> MangaObject {
        let record = MangaObject(context: context)
        record.sourceId = "test"
        record.id = "manga"
        record.title = "Test Manga"
        return record
    }
}
