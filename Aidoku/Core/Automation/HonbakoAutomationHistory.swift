#if SUMI
import CoreData
import Foundation

enum HonbakoAutomationHistory {
    struct Entry: Codable, Sendable {
        let sourceId: String
        let mangaId: String
        let chapterId: String
        let title: String
        let chapterTitle: String
        let chapterNumber: Float?
        let volumeNumber: Float?
        let page: Int?
        let totalPages: Int?
        let completed: Bool
        let readAt: String
    }
    struct Page: Codable, Sendable {
        let entries: [Entry]
        let nextOffset: Int?
        let before: String
        let observedAt: String
        var coverage = "saved_chapter_history"
        let excludedRecords: Int
    }

    private static func number(_ value: NSNumber?) -> Float? {
        guard let value = value?.floatValue, value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// Fetch each page independently; history is not restricted to library books
    /// or included in the routine library snapshot. Private reading creates no history.
    static func page(offset: Int, limit: Int, before: String, context: NSManagedObjectContext) throws -> Page {
        guard offset >= 0, offset <= 2_147_483_646, (1...100).contains(limit),
              let boundary = (try? Date(before, strategy: .iso8601))
                ?? (try? Date(before, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))) else { throw HonbakoAutomationPolicy.Failure.invalidJob }
        let request = HistoryObject.fetchRequest()
        request.predicate = NSPredicate(format: "dateRead <= %@", boundary as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: "dateRead", ascending: false), NSSortDescriptor(key: "sourceId", ascending: true),
            NSSortDescriptor(key: "mangaId", ascending: true), NSSortDescriptor(key: "chapterId", ascending: true)]
        request.fetchOffset = offset
        request.fetchLimit = limit + 1
        let records = try context.fetch(request)
        let entries: [Entry] = records.prefix(limit).compactMap { history in
            guard HonbakoAutomationPolicy.validItem(.init(sourceId: history.sourceId, mangaId: history.mangaId)),
                  HonbakoAutomationPolicy.exportableIdentifier(history.chapterId), !history.chapterId.isEmpty,
                  history.chapterId.utf8.count <= 2048, let date = history.dateRead else { return nil }
            let manga = CoreDataManager.shared.getManga(mangaId: .init(sourceKey: history.sourceId, mangaKey: history.mangaId), context: context)
            let chapter = history.chapter
            return Entry(sourceId: history.sourceId, mangaId: history.mangaId, chapterId: history.chapterId,
                title: String((manga?.title ?? history.mangaId).prefix(500)), chapterTitle: String((chapter?.title ?? history.chapterId).prefix(500)),
                chapterNumber: number(chapter?.chapter),
                volumeNumber: number(chapter?.volume),
                page: history.progress >= 1 ? Int(history.progress) : nil, totalPages: history.total >= 1 ? Int(history.total) : nil,
                completed: history.completed, readAt: date.ISO8601Format())
        }
        return Page(entries: entries, nextOffset: records.count > limit ? offset + limit : nil, before: before,
            observedAt: Date.now.ISO8601Format(), excludedRecords: min(records.count, limit) - entries.count)
    }
}
#endif
