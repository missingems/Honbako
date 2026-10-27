@testable import Sumi
import AidokuRunner
import CoreData
import Foundation
import Testing

@Suite(.serialized)
struct HonbakoPersonalEnglishImportTests {
    @Test("Only an owner build plus an explicit setup request may import")
    func signedPersonalGate() {
        #expect(!HonbakoPersonalEnglishImport.isRequested(personalFeaturesEnabled: false,
            arguments: ["--honbako-import-english-50"], infoFlag: "YES"))
        #expect(!HonbakoPersonalEnglishImport.isRequested(personalFeaturesEnabled: true, arguments: [], infoFlag: "NO"))
        #expect(HonbakoPersonalEnglishImport.isRequested(personalFeaturesEnabled: true,
            arguments: ["--honbako-import-english-50"], infoFlag: nil))
        #expect(HonbakoPersonalEnglishImport.isRequested(personalFeaturesEnabled: true, arguments: [], infoFlag: "YES"))
    }

    @Test("Personal selection keeps source rank, skips unreadable titles, deduplicates and bounds concurrency")
    func rankedReadableEnglishOnly() async throws {
        let activity = Activity()
        let catalog = HonbakoPersonalEnglishCatalog(
            pageLoader: { page in
                if page == 1 {
                    return .init(entries: (1...4).map(Self.manga), hasNextPage: true)
                }
                return .init(entries: [Self.manga(4), Self.manga(5), Self.manga(6)], hasNextPage: false)
            },
            chapterLoader: { manga in
                await activity.start()
                try await Task.sleep(for: .milliseconds(manga.key == Self.id(1) ? 15 : 2))
                await activity.end()
                if manga.key == Self.id(2) { return [] }
                return [Self.chapter("newest", number: 5), Self.chapter("oldest", number: 1),
                    Self.chapter("japanese", language: "ja"), Self.chapter("locked", locked: true)]
            },
            pageVerifier: { manga, chapter in
                #expect(chapter.key == "oldest", "The first real English chapter must be openable")
                return manga.key == Self.id(3) ? 0 : 24
            }, concurrency: 2)
        let result = try await catalog.prepare(count: 3)
        #expect(result.entries.map(\.manga.key) == [Self.id(1), Self.id(4), Self.id(5)])
        #expect(result.entries.map(\.rank) == [1, 4, 6])
        #expect(result.entries.allSatisfy { $0.chapters.count == 2 && $0.verifiedPageCount == 24 })
        #expect(result.errors.count == 2)
        #expect(await activity.maximum == 2)
    }

    @Test("An insufficient English catalog is reported honestly, with no invented fallback entries")
    func insufficientAvailability() async throws {
        let catalog = HonbakoPersonalEnglishCatalog(
            pageLoader: { _ in .init(entries: [Self.manga(1), Self.manga(2)], hasNextPage: false) },
            chapterLoader: { _ in [Self.chapter("real")] }, pageVerifier: { _, _ in 12 })
        let result = try await catalog.prepare(count: 50)
        #expect(result.entries.count == 2)
        #expect(Set(result.entries.map(\.manga.key)).count == 2)
    }

    @MainActor
    @Test("The batch adds once, selects English for new titles and preserves existing history, dates and languages")
    func transactionalIdempotenceAndBookmarks() throws {
        let context = try Self.makeContext()
        let manager = CoreDataManager.shared
        let savedManga = Self.manga(1)
        let savedChapter = Self.chapter("saved-ja", language: "ja")
        manager.addToLibrary(manga: savedManga, chapters: [savedChapter], context: context)
        let object = try #require(manager.getManga(mangaId: savedManga.identifier, context: context))
        object.langFilter = "ja"
        let opened = Date(timeIntervalSince1970: 100)
        object.libraryObject?.lastOpened = opened
        let history = manager.getOrCreateHistory(chapterId: .init(sourceKey: savedManga.sourceKey,
            mangaKey: savedManga.key, chapterKey: savedChapter.key), context: context)
        history.progress = 19
        history.completed = false
        history.dateRead = Date(timeIntervalSince1970: 200)
        try context.save()

        let entries = [Self.entry(1), Self.entry(2), Self.entry(2)]
        let first = try HonbakoPersonalEnglishImport.commit(entries, context: context)
        #expect(first.added == [Self.manga(2).identifier])
        #expect(first.existing == 1)
        #expect(manager.getLibraryManga(context: context).count == 2)
        #expect(manager.getHistory(context: context).count == 1)
        #expect(history.progress == 19 && !history.completed)
        #expect(object.langFilter == "ja")
        #expect(object.libraryObject?.lastOpened == opened)
        #expect(manager.getChapters(mangaId: savedManga.identifier, context: context).map(\.id) == ["saved-ja"])
        let newManga = try #require(manager.getManga(mangaId: Self.manga(2).identifier, context: context))
        #expect(newManga.langFilter == "en")
        #expect(newManga.libraryObject?.lastRead == nil)
        #expect(manager.getChapters(mangaId: newManga.identifier, context: context).count == 1)

        let second = try HonbakoPersonalEnglishImport.commit(entries, context: context)
        #expect(second.added.isEmpty && second.existing == 2)
        #expect(manager.getLibraryManga(context: context).count == 2)
        #expect(manager.getHistory(context: context).count == 1)
    }

    @MainActor
    @Test("Adding an already-read search result preserves its untranslated bookmark and language preference")
    func unsavedHistoryIsPreserved() throws {
        let context = try Self.makeContext()
        let manager = CoreDataManager.shared
        let manga = Self.manga(1)
        let object = manager.getOrCreateManga(manga, context: context)
        object.langFilter = nil
        let chapter = Self.chapter("legacy-ja", language: "ja")
        manager.setChapters([chapter], mangaId: manga.identifier, context: context)
        let history = manager.getOrCreateHistory(chapterId: .init(sourceKey: manga.sourceKey,
            mangaKey: manga.key, chapterKey: chapter.key), context: context)
        history.progress = 7
        try context.save()

        _ = try HonbakoPersonalEnglishImport.commit([Self.entry(1)], context: context)
        #expect(object.langFilter == nil)
        #expect(history.progress == 7)
        #expect(history.chapter?.id == "legacy-ja")
        #expect(Set(manager.getChapters(mangaId: manga.identifier, context: context).map(\.id)) == ["real-en", "legacy-ja"])
        #expect(manager.getHistory(context: context).count == 1)
    }

    @MainActor
    @Test("A restart after database save reuses the durable fifty instead of importing a later ranking")
    func durableSelectionSurvivesPostSaveRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HonbakoPersonalEnglishManifestStore(url: directory.appending(path: "selection.json"))
        let first = try await store.loadOrPrepare {
            .init(entries: (1...50).map(Self.entry), errors: [])
        }
        let context = try Self.makeContext()
        let firstCommit = try HonbakoPersonalEnglishImport.commit(first.prepared.entries, context: context)
        #expect(firstCommit.added.count == 50)

        // Simulate termination before the separate completion preference was
        // written. Even if rankings now differ, the loader must not run again.
        let restartedStore = HonbakoPersonalEnglishManifestStore(url: store.url)
        let retry = try await restartedStore.loadOrPrepare {
            Issue.record("A durable selection must never fetch a new ranked list")
            return .init(entries: (51...100).map(Self.entry), errors: [])
        }
        #expect(retry.prepared.entries.map(\.manga.identifier) == first.prepared.entries.map(\.manga.identifier))
        #expect(retry.prepared.entries.allSatisfy { $0.manga.sourceKey == HonbakoMangaDexRunner.sourceKey })
        #expect(retry.prepared.entries.first?.chapters.first?.key == "real-en")
        let retryCommit = try HonbakoPersonalEnglishImport.commit(retry.prepared.entries, context: context)
        #expect(retryCommit.added.isEmpty && retryCommit.existing == 50)
        #expect(CoreDataManager.shared.getLibraryManga(context: context).count == 50)
        #expect(CoreDataManager.shared.getHistory(context: context).isEmpty)
    }

    @Test("An incomplete catalog does not freeze a selection before fifty have been accepted")
    func incompleteSelectionCanRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HonbakoPersonalEnglishManifestStore(url: directory.appending(path: "selection.json"))
        let incomplete = try await store.loadOrPrepare { .init(entries: [Self.entry(1)], errors: []) }
        #expect(incomplete.prepared.entries.count == 1)
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
        let complete = try await store.loadOrPrepare { .init(entries: (1...50).map(Self.entry), errors: []) }
        #expect(complete.prepared.entries.count == 50)
        #expect(FileManager.default.fileExists(atPath: store.url.path))
    }

    @Test("A damaged saved selection fails closed rather than silently choosing fifty different books")
    func damagedSelectionDoesNotRerank() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = HonbakoPersonalEnglishManifestStore(url: directory.appending(path: "selection.json"))
        try Data("{}".utf8).write(to: store.url, options: .atomic)
        await #expect(throws: (any Error).self) {
            try await store.loadOrPrepare {
                Issue.record("An unreadable manifest must not be replaced with a new ranking")
                return .init(entries: (51...100).map(Self.entry), errors: [])
            }
        }
    }

    private actor Activity {
        var count = 0
        var maximum = 0
        func start() { count += 1; maximum = max(maximum, count) }
        func end() { count -= 1 }
    }

    private static func id(_ index: Int) -> String {
        "00000000-0000-4000-8000-" + String(repeating: "0", count: 12 - String(index).count) + String(index)
    }

    private static func manga(_ index: Int) -> AidokuRunner.Manga {
        .init(sourceKey: HonbakoMangaDexRunner.sourceKey, key: id(index), title: "Fixture \(index)", viewer: .rightToLeft)
    }

    private static func chapter(_ key: String, number: Float = 1, language: String = "en", locked: Bool = false) -> AidokuRunner.Chapter {
        .init(key: key, chapterNumber: number, language: language, locked: locked)
    }

    private static func entry(_ index: Int) -> HonbakoPersonalEnglishCatalog.Entry {
        .init(rank: index, manga: manga(index), chapters: [chapter("real-en")],
            verifiedChapterID: "real-en", verifiedPageCount: 12)
    }

    @MainActor
    private static func makeContext() throws -> NSManagedObjectContext {
        let original = try #require(NSManagedObjectModel.mergedModel(from: [Bundle(for: CoreDataManager.self)]))
        let model = try #require(original.copy() as? NSManagedObjectModel)
        for entity in model.entities {
            entity.properties = entity.properties.filter { !($0 is NSDerivedAttributeDescription) }
        }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }
}
