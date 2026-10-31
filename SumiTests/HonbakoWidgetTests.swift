@testable import Sumi
import CoreData
import Foundation
import Testing

struct HonbakoWidgetTests {
    @Test("Resume URLs preserve source keys, Unicode and encoded manga paths")
    func resumeRoutes() throws {
        let book = HonbakoWidgetSnapshot.Book(sourceID: "server.local", mangaID: "日本語/a?b#c%20", title: "Example")
        let url = try #require(book.resumeURL)
        let target = try #require(HonbakoWidgetSnapshot.resumeTarget(from: url))
        #expect(target.source == book.sourceID)
        #expect(target.manga == book.mangaID)
        #expect(HonbakoWidgetSnapshot.resumeTarget(from: URL(string: "honbako://widget/resume?source=a&source=b&manga=c")!) == nil)
        #expect(HonbakoWidgetSnapshot.resumeTarget(from: URL(string: "https://widget/resume?source=a&manga=c")!) == nil)
    }

    @Test("Pro expiry hides history and updates while retaining free resume")
    func proExpiry() {
        let date = Date.now
        var snapshot = HonbakoWidgetSnapshot.preview
        snapshot.proExpiresAt = date
        #expect(snapshot.hasPro(at: date.addingTimeInterval(-1)))
        #expect(!snapshot.hasPro(at: date))
        let locked = snapshot.removingLockedData(at: date)
        #expect(locked.resume == snapshot.resume)
        #expect(locked.updates.isEmpty)
        #expect(locked.readingDays.isEmpty)
    }

    @Test("Expiry is scheduled even when it is later than a normal reload")
    func timelineBoundaries() throws {
        let now = Date.now
        var snapshot = HonbakoWidgetSnapshot.preview
        let expiry = now.addingTimeInterval(10 * 86400)
        snapshot.proExpiresAt = expiry
        let dates = snapshot.timelineDates(now: now)
        #expect(dates.first == now)
        #expect(dates.contains(expiry))
        #expect(dates == dates.sorted())
        #expect(dates.count == 9)
        #expect(snapshot.removingLockedData(at: expiry).readingDays.isEmpty)
    }

    @Test("Reading sessions split at local midnight and reject negative or future time")
    func readingDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let midnight = Date(timeIntervalSince1970: 1_700_006_400)
        let today = calendar.startOfDay(for: midnight)
        let now = today.addingTimeInterval(1800)
        let days = HonbakoWidgetSnapshot.readingDays(sessions: [
            (today.addingTimeInterval(-600), today.addingTimeInterval(600)),
            (today.addingTimeInterval(900), now.addingTimeInterval(300)),
            (now, today)
        ], now: now, calendar: calendar)
        let snapshot = HonbakoWidgetSnapshot(generatedAt: now, resume: nil, updates: [], readingDays: days)
        #expect(snapshot.secondsRead(on: now, calendar: calendar) == 1500)
        #expect(snapshot.secondsRead(on: today.addingTimeInterval(-1), calendar: calendar) == 600)
        #expect(days.count == 7)
    }

    @Test("Shared snapshots fail safely and cover names cannot escape the cover folder")
    func sharedFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(HonbakoWidgetSnapshot.read(from: directory) == .empty)
        let snapshot = HonbakoWidgetSnapshot.preview
        try JSONEncoder().encode(snapshot).write(to: directory.appendingPathComponent(HonbakoWidgetSnapshot.fileName))
        #expect(HonbakoWidgetSnapshot.read(from: directory) == snapshot)
        #expect(HonbakoWidgetSnapshot.coverURL(file: "../private.jpg", directory: directory) == nil)
        #expect(HonbakoWidgetSnapshot.coverURL(file: "nested/cover.jpg", directory: directory) == nil)
        #expect(HonbakoWidgetSnapshot.coverURL(file: "safe.jpg", directory: directory)?.lastPathComponent == "safe.jpg")
    }

    @Test("Capture uses real saved-library history and excludes viewed, read and removed updates")
    @MainActor
    func capture() throws {
        let model = try #require(NSManagedObjectModel.mergedModel(from: [Bundle(for: CoreDataManager.self)])?.copy() as? NSManagedObjectModel)
        for entity in model.entities { entity.properties = entity.properties.filter { !($0 is NSDerivedAttributeDescription) } }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let manga = MangaObject(context: context)
        manga.id = "example"; manga.sourceId = "local"; manga.title = "Our Manga"
        let library = LibraryMangaObject(context: context)
        library.manga = manga
        let chapter = ChapterObject(context: context)
        chapter.id = "1"; chapter.sourceId = "local"; chapter.mangaId = "example"; chapter.manga = manga
        chapter.chapter = 1
        let history = HistoryObject(context: context)
        history.sourceId = "local"; history.mangaId = "example"; history.chapterId = "1"
        history.chapter = chapter; history.dateRead = .now; history.progress = 7; history.total = 20
        let update = MangaUpdateObject(context: context)
        update.chapter = chapter; update.sourceId = "local"; update.mangaId = "example"; update.chapterId = "1"; update.date = .now
        let now = Date.now
        let free = try HonbakoWidgetPublisher.capture(context: context, now: now, proExpiry: nil).0
        #expect(free.resume?.title == "Our Manga")
        #expect(free.resume?.page == 7)
        #expect(free.updates.isEmpty)
        let pro = try HonbakoWidgetPublisher.capture(context: context, now: now, proExpiry: now.addingTimeInterval(3600)).0
        #expect(pro.updates.count == 1)
        update.viewed = true
        #expect(try HonbakoWidgetPublisher.capture(context: context, now: now, proExpiry: now.addingTimeInterval(3600)).0.updates.isEmpty)
        update.viewed = false
        history.completed = true
        #expect(try HonbakoWidgetPublisher.capture(context: context, now: now, proExpiry: now.addingTimeInterval(3600)).0.updates.isEmpty)
        context.delete(library)
        let removed = try HonbakoWidgetPublisher.capture(context: context, now: now, proExpiry: nil).0
        #expect(removed.resume == nil)
    }
}
