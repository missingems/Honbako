#if SUMI
import Combine
import CoreData
import CryptoKit
import Foundation
import UIKit
import WidgetKit

@MainActor
final class HonbakoWidgetPublisher {
    static let shared = HonbakoWidgetPublisher()
    private var observations: Set<AnyCancellable> = []
    private var refreshTask: Task<Void, Never>?
    private var needsRefresh = false
    private var needsForcedReload = false
    private var isRefreshing = false
    private var lastTimelineReload = Date.distantPast
    private var pendingKinds: Set<String> = []

    func start() {
        guard observations.isEmpty else { return }
        for name in [Notification.Name.NSManagedObjectContextDidSave, .updateLibrary, .updateHistory,
                     .historyRemoved, .historySet, .mangaUpdatesViewed,
                     HonbakoProStore.entitlementChangedNotification, .init("Honbako.Widgets.Entitlement"),
                     SumiCoverArtworkLoader.batchPreparedNotification,
                     UIApplication.didBecomeActiveNotification] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.schedule() }
                .store(in: &observations)
        }
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.publish(forceReload: true) }
            }.store(in: &observations)
        schedule()
    }

    private func schedule(forceReload: Bool = false) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.refreshTask = nil
            await self?.publish(forceReload: forceReload)
        }
    }

    func publish(forceReload: Bool = false) async {
        guard let directory = HonbakoWidgetSnapshot.containerURL else { return }
        // Serialize writes, but retain an event received while covers are loading.
        guard !isRefreshing else {
            needsRefresh = true
            needsForcedReload = needsForcedReload || forceReload
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            if needsRefresh {
                needsRefresh = false
                let force = needsForcedReload
                needsForcedReload = false
                schedule(forceReload: force)
            }
        }
        let background = UIApplication.shared.beginBackgroundTask(withName: "Update reading widgets")
        defer {
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
        }
        do {
            let now = Date.now
            let proExpiry = HonbakoProStore.shared.widgetAccessExpiration
            let old = HonbakoWidgetSnapshot.read(from: directory)
            var (snapshot, books) = try await CoreDataManager.shared.container.performBackgroundTask { context in
                try Self.capture(context: context, now: now, proExpiry: proExpiry)
            }
            let covers = directory.appendingPathComponent("covers", isDirectory: true)
            try FileManager.default.createDirectory(at: covers, withIntermediateDirectories: true)
            var coverFiles: [String: String] = [:]
            // Copy already-loaded artwork only: no network on the reading or
            // background path. A maximum of seven bounded cover files; no source keys or secrets
            // are needed by the extension to render them.
            for book in books {
                guard let cover = book.coverURL else { continue }
                let identity = book.id.sourceKey + "\u{0}" + book.id.mangaKey + "\u{0}" + cover.absoluteString
                let name = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined() + ".jpg"
                let destination = covers.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: destination.path),
                   let image = SumiCoverArtworkLoader.shared.cachedCover(for: book) {
                    let size = CGSize(width: 240, height: 360)
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1
                    let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                        let scale = max(size.width / max(1, image.size.width), size.height / max(1, image.size.height))
                        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        image.draw(in: CGRect(x: (size.width - target.width) / 2, y: (size.height - target.height) / 2,
                                              width: target.width, height: target.height))
                    }
                    if let data = scaled.jpegData(compressionQuality: 0.85) {
                        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    }
                }
                let id = book.id.sourceKey + "\u{0}" + book.id.mangaKey
                if FileManager.default.fileExists(atPath: destination.path) {
                    coverFiles[id] = name
                } else {
                    let oldFile = ([old.resume].compactMap { $0 } + old.updates).first { $0.id == id }?.coverFile
                    if let oldFile, let url = HonbakoWidgetSnapshot.coverURL(file: oldFile, directory: directory),
                       FileManager.default.fileExists(atPath: url.path) { coverFiles[id] = oldFile }
                }
            }
            if var resume = snapshot.resume {
                resume.coverFile = coverFiles[resume.id]
                snapshot.resume = resume
            }
            for index in snapshot.updates.indices { snapshot.updates[index].coverFile = coverFiles[snapshot.updates[index].id] }
            snapshot = snapshot.removingLockedData(at: .now)
            // Avoid spending WidgetKit reload budget on identical database saves.
            var comparable = snapshot
            comparable.generatedAt = old.generatedAt
            let accessChanged = old.proExpiresAt != snapshot.proExpiresAt
            if old.resume != snapshot.resume { pendingKinds.insert(HonbakoWidgetSnapshot.resumeKind) }
            if accessChanged || old.readingDays != snapshot.readingDays { pendingKinds.insert(HonbakoWidgetSnapshot.timeKind) }
            if accessChanged || old.updates != snapshot.updates || old.libraryCheckedAt != snapshot.libraryCheckedAt {
                pendingKinds.insert(HonbakoWidgetSnapshot.updatesKind)
            }
            if comparable != old {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: directory.appendingPathComponent(HonbakoWidgetSnapshot.fileName),
                               options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            // Persist frequently, but spend each widget's reload budget only on
            // its own changed content; flush coalesced page progress on background.
            if forceReload || accessChanged || now.timeIntervalSince(lastTimelineReload) >= 60 {
                lastTimelineReload = now
                for kind in pendingKinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
                pendingKinds.removeAll()
            }
            let retained = Set(([snapshot.resume?.coverFile] + snapshot.updates.map(\.coverFile)).compactMap { $0 })
            for file in (try? FileManager.default.contentsOfDirectory(at: covers, includingPropertiesForKeys: nil)) ?? []
                where !retained.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
            books.removeAll()
        } catch {
            // Preserve the last good snapshot on database or disk failure.
            LogManager.logger.error("Widget snapshot update failed: \(error.localizedDescription)")
        }
    }

    nonisolated static func capture(context: NSManagedObjectContext, now: Date,
                                     proExpiry: Date?) throws -> (HonbakoWidgetSnapshot, [SumiBook]) {
        let historyRequest = HistoryObject.fetchRequest()
        historyRequest.predicate = NSPredicate(format: "chapter.manga.libraryObject != nil AND dateRead > %@", Date.distantPast as NSDate)
        historyRequest.sortDescriptors = [NSSortDescriptor(key: "dateRead", ascending: false)]
        historyRequest.fetchLimit = 1
        let history = try context.fetch(historyRequest).first
        var coverBooks: [SumiBook] = []
        var resume: HonbakoWidgetSnapshot.Book?
        if let history, let manga = CoreDataManager.shared.getManga(mangaId: history.identifier.mangaIdentifier, context: context) {
            resume = widgetBook(manga: manga, chapter: history.chapter)
            resume?.page = history.completed ? nil : max(1, Int(history.progress))
            resume?.totalPages = history.total > 0 ? Int(history.total) : nil
            coverBooks.append(SumiBook(manga: manga.toNewManga()))
        }
        var updates: [HonbakoWidgetSnapshot.Book] = []
        var days: [HonbakoWidgetSnapshot.ReadingDay] = []
        if proExpiry.map({ $0 > now }) == true {
            let updateRequest = MangaUpdateObject.fetchRequest()
            updateRequest.predicate = NSPredicate(format: "viewed == NO AND chapter.manga.libraryObject != nil AND chapter.locked == NO AND (chapter.history == nil OR chapter.history.completed == NO)")
            updateRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            let records = try context.fetch(updateRequest)
            var indices: [String: Int] = [:]
            for record in records {
                guard let chapter = record.chapter, let manga = chapter.manga,
                      ChapterNotificationPolicy.matchesFilters(chapter.toNewChapter(), languageFilter: manga.langFilter,
                          scanlatorFilter: manga.scanlatorFilter ?? []) else { continue }
                let id = manga.sourceId + "\u{0}" + manga.id
                if let index = indices[id] { updates[index].updateCount += 1 }
                else if updates.count < 6 {
                    indices[id] = updates.count
                    var item = widgetBook(manga: manga, chapter: chapter)
                    item.updateCount = 1
                    updates.append(item)
                    if !coverBooks.contains(where: { $0.id == manga.identifier }) { coverBooks.append(SumiBook(manga: manga.toNewManga())) }
                }
            }
            let request = ReadingSessionObject.fetchRequest()
            let weekStart = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: now)) ?? now
            request.predicate = NSPredicate(format: "endDate >= %@", weekStart as NSDate)
            let sessions = try context.fetch(request).compactMap { session -> (start: Date, end: Date)? in
                guard let start = session.startDate, let end = session.endDate, end >= start else { return nil }
                return (start, end)
            }
            days = HonbakoWidgetSnapshot.readingDays(sessions: sessions, now: now)
        }
        let library = CoreDataManager.shared.getLibraryManga(context: context)
        let checked = library.map(\.lastUpdatedChapters).max()
        return (.init(generatedAt: now, proExpiresAt: proExpiry, resume: resume,
                      updates: updates, readingDays: days, libraryCheckedAt: checked), coverBooks)
    }

    nonisolated private static func widgetBook(manga: MangaObject, chapter: ChapterObject?) -> HonbakoWidgetSnapshot.Book {
        let chapterLabel: String?
        if let number = chapter?.chapter {
            chapterLabel = String(localized: "Chapter \(String(format: "%g", number.doubleValue))")
        } else { chapterLabel = chapter?.title }
        return .init(sourceID: manga.sourceId, mangaID: manga.id, title: manga.title,
                     chapter: chapterLabel)
    }
}
#endif
