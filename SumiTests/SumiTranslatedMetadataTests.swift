@testable import Sumi
import AidokuRunner
import CoreData
import Foundation
import Testing

@MainActor
struct SumiTranslatedMetadataTests {
    @Test("A source-language refresh keeps other translations but removes stale chapters in represented languages")
    func partialLanguageRefresh() {
        let existing = [chapter("en-old", "en"), chapter("ja-saved", "ja"), chapter("unknown", nil)]
        let incoming = [chapter("en-new", "en")]
        let kept = SumiChapterLanguage.retainingOtherLanguages(existing: existing, fetched: incoming)
        #expect(Set(kept.map(\.key)) == ["en-new", "ja-saved"])
        let allLanguages = incoming + [chapter("ja-new", "ja")]
        let replaced = SumiChapterLanguage.retainingOtherLanguages(existing: existing, fetched: allLanguages)
        #expect(Set(replaced.map(\.key)) == ["en-new", "ja-new"])
    }

    @Test("Unknown source languages cannot remove a specifically cached translation")
    func unlabeledResponse() {
        let kept = SumiChapterLanguage.retainingOtherLanguages(existing: [chapter("ja", "ja")],
                                                               fetched: [chapter("unknown", nil)])
        #expect(Set(kept.map(\.key)) == ["ja", "unknown"])
    }

    @Test("A partial language update preserves the exact source order of specials and volume resets")
    func sourceOrderIsAuthoritative() {
        let incoming: [AidokuRunner.Chapter] = [
            .init(key: "volume-2-ch1", chapterNumber: 1, volumeNumber: 2, language: "en"),
            .init(key: "volume-1-ch9", chapterNumber: 9, volumeNumber: 1, language: "en"),
            .init(key: "volume-1-ch8", chapterNumber: 8, volumeNumber: 1, language: "en")
        ]
        let merged = SumiChapterLanguage.retainingOtherLanguages(existing: [chapter("ja-saved", "ja")], fetched: incoming)
        #expect(SumiChapterLanguage.filter(merged, language: "en").map(\.key) == incoming.map(\.key))
    }

    @Test("Applying a default-language update retains the translated chapter object and its history link")
    func persistentTranslationSurvives() throws {
        let context = try makeContext()
        let manager = CoreDataManager.shared
        let manga = AidokuRunner.Manga(sourceKey: "translation-test", key: "title", title: "Title", viewer: .webtoon)
        manager.createManga(manga, context: context)
        manager.setChapters([chapter("en-old", "en"), chapter("ja-bookmark", "ja")], mangaId: manga.identifier, context: context)
        let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: "ja-bookmark")
        let japanese = try #require(manager.getChapter(chapterId: identifier, context: context))
        let history = HistoryObject(context: context)
        history.sourceId = manga.sourceKey
        history.mangaId = manga.key
        history.chapterId = "ja-bookmark"
        history.progress = 7
        history.dateRead = .now
        japanese.history = history
        try context.save()
        let savedID = japanese.objectID

        manager.setChapters([chapter("en-new", "en")], mangaId: manga.identifier, context: context)
        try context.save()
        let retained = try #require(manager.getChapter(chapterId: identifier, context: context))
        #expect(retained.objectID == savedID)
        #expect(retained.history?.progress == 7)
        #expect(retained.history?.chapterId == "ja-bookmark")
        #expect(Set(manager.getChapters(mangaId: manga.identifier, context: context).map(\.id)) == ["en-new", "ja-bookmark"])
    }

    @Test("Partial metadata cannot erase a stored vertical reader mode in either source model")
    func viewerHintSurvives() throws {
        let context = try makeContext()
        let original = AidokuRunner.Manga(sourceKey: "viewer-test", key: "title", title: "Title", viewer: .webtoon)
        let object = CoreDataManager.shared.createManga(original, context: context)
        let partial = AidokuRunner.Manga(sourceKey: original.sourceKey, key: original.key, title: "Updated")
        object.load(from: partial)
        #expect(object.toNewManga().viewer == .webtoon)
        #expect(SumiMangaMetadata.merging(original, with: partial).viewer == .webtoon)
        let legacy = object.toManga()
        legacy.viewer = .defaultViewer
        object.load(from: legacy)
        #expect(object.toNewManga().viewer == .webtoon)
        object.load(from: partial, override: true)
        #expect(object.toNewManga().viewer == .unknown)
    }

    private func chapter(_ key: String, _ language: String?) -> AidokuRunner.Chapter {
        .init(key: key, chapterNumber: 1, language: language)
    }

    private func makeContext() throws -> NSManagedObjectContext {
        let model = try #require(NSManagedObjectModel.mergedModel(from: [Bundle(for: CoreDataManager.self)]))
        let testModel = model.copy() as! NSManagedObjectModel
        for entity in testModel.entities {
            entity.properties = entity.properties.filter { !($0 is NSDerivedAttributeDescription) }
        }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: testModel)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }
}
