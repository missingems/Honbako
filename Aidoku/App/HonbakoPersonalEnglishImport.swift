#if SUMI
import AidokuRunner
import CoreData
import Foundation
import UIKit

/// A signed owner build plus an explicit setup argument or signed setup flag
/// are both required.
/// Ordinary installs do not install sources, fetch a feed, or add any manga.
@MainActor
enum HonbakoPersonalEnglishImport {
    nonisolated static let argument = "--honbako-import-english-50"
    private static let completionKey = "Honbako.PersonalEnglish50.v1.Completed"
    private static let receiptName = "HonbakoEnglishImportResult.json"
    private static var isRunning = false

    struct Receipt: Encodable {
        struct Title: Encodable {
            let id: String
            let title: String
            let rank: Int
            let language: String
            let chapterCount: Int
            let verifiedChapterId: String
            let verifiedPageCount: Int
        }
        var status = "preparing"
        var count = 0
        var added = 0
        var existing = 0
        let sourceId = HonbakoMangaDexRunner.sourceKey
        let ranking = "MangaDex order[followedCount]=desc; availableTranslatedLanguage[]=en; safe/suggestive"
        var validatedAt: Date?
        var titles: [Title] = []
        var errors: [String] = []
    }

    static func runIfRequested() async {
        guard isRequested(personalFeaturesEnabled: HonbakoProStore.personalFeaturesEnabled,
            arguments: ProcessInfo.processInfo.arguments,
            infoFlag: Bundle.main.object(forInfoDictionaryKey: "HonbakoImportEnglish50") as? String),
              !isRunning else { return }
        // A completed import remains completed if its books are later removed.
        // Relaunching with the same argument never repopulates a curated library.
        if UserDefaults.standard.bool(forKey: completionKey) { return }
        isRunning = true
        let previousIdleSetting = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            isRunning = false
            UIApplication.shared.isIdleTimerDisabled = previousIdleSetting
        }
        var receipt = Receipt()
        write(receipt)
        let suite = "Honbako.PersonalEnglishImport.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        defer { defaults.removePersistentDomain(forName: suite) }
        // An isolated preference domain keeps the import English-only without
        // altering any existing source-wide or per-title language preference.
        defaults.set(["en"], forKey: HonbakoMangaDexRunner.sourceKey + ".languages")
        let transport = HonbakoPersonalImportTransport()
        let runner = HonbakoMangaDexRunner(defaults: defaults, transport: { try await transport.fetch($0) })
        let catalog = HonbakoPersonalEnglishCatalog(
            pageLoader: { try await runner.getSearchMangaList(query: nil, page: $0, filters: []) },
            chapterLoader: { try await runner.chapters(for: $0, language: "en") },
            pageVerifier: { try await runner.getPageList(manga: $0, chapter: $1).count })
        do {
            let selectionStore = HonbakoPersonalEnglishManifestStore(url: URL.documentsDirectory
                .appending(path: "HonbakoEnglishImportSelection.json"))
            let selection = try await selectionStore.loadOrPrepare { try await catalog.prepare() }
            let prepared = selection.prepared
            receipt.validatedAt = selection.validatedAt
            receipt.count = prepared.entries.count
            receipt.errors = prepared.errors
            receipt.titles = prepared.entries.map { entry in
                .init(id: entry.manga.key, title: entry.manga.title, rank: entry.rank, language: "en",
                    chapterCount: entry.chapters.count, verifiedChapterId: entry.verifiedChapterID,
                    verifiedPageCount: entry.verifiedPageCount)
            }
            guard prepared.entries.count == 50 else {
                receipt.status = "insufficient-readable-english-titles"
                write(receipt)
                return
            }

            let sources = SourceManager.shared
            await sources.waitForSourcesLoad()
            await sources.enable(sourceKey: HonbakoMangaDexRunner.sourceKey)
            if await sources.source(for: HonbakoMangaDexRunner.sourceKey) == nil {
                _ = await sources.createCustomSource(.honbakoMangaDex)
            }
            guard await sources.source(for: HonbakoMangaDexRunner.sourceKey) != nil else {
                receipt.status = "failed"
                receipt.errors.append("The native English source could not be activated.")
                write(receipt)
                return
            }

            let summary = try await CoreDataManager.shared.container.performBackgroundTask { context in
                try commit(prepared.entries, context: context)
            }
            receipt.added = summary.added.count
            receipt.existing = summary.existing
            receipt.status = "finished"
            write(receipt)
            UserDefaults.standard.set(true, forKey: completionKey)
            // New titles inherit the existing default-on alert preference;
            // existing titles retain explicit opt-outs and all reading history.
            for identifier in summary.added {
                if !HonbakoChapterAlerts.preferenceEnabled(for: identifier) { continue }
                HonbakoChapterAlerts.setPreference(true, for: identifier)
            }
            NotificationCenter.default.post(name: .updateLibrary, object: nil)
        } catch {
            receipt.status = "failed"
            receipt.errors.append("The personal English import could not finish; the library was not replaced.")
            write(receipt)
            LogManager.logger.error("Personal English library setup failed: \(error.localizedDescription)")
        }
    }

    struct CommitSummary: Sendable {
        let added: [MangaIdentifier]
        let existing: Int
    }

    nonisolated static func isRequested(personalFeaturesEnabled: Bool, arguments: [String], infoFlag: String?) -> Bool {
        personalFeaturesEnabled && (arguments.contains(argument) || infoFlag == "YES")
    }

    /// One context/save publishes the entire batch. Existing library entries,
    /// chapter histories, language choices, and opening dates are left intact.
    nonisolated static func commit(_ entries: [HonbakoPersonalEnglishCatalog.Entry],
                                   context: NSManagedObjectContext) throws -> CommitSummary {
        let manager = CoreDataManager.shared
        var added: [MangaIdentifier] = []
        var existing = 0
        var seen: Set<MangaIdentifier> = []
        for entry in entries where seen.insert(entry.manga.identifier).inserted {
            let identifier = entry.manga.identifier
            if manager.hasLibraryManga(mangaId: identifier, context: context) {
                existing += 1
                continue
            }
            // An unsaved search result may already have reading history. Adding
            // it must not overwrite the language in which it was being read.
            let oldManga = manager.getManga(mangaId: identifier, context: context)
            let oldLanguage = oldManga?.langFilter
            let hadManga = oldManga != nil
            let storedChapters = manager.getChapters(mangaId: identifier, context: context).map { $0.toNewChapter() }
            let chapters = SumiChapterLanguage.merge(storedChapters, with: entry.chapters)
            manager.addToLibrary(manga: entry.manga, chapters: chapters, context: context)
            manager.getManga(mangaId: identifier, context: context)?.langFilter = hadManga ? oldLanguage : "en"
            // Library insertion normally stamps lastRead. An import has not
            // read anything: use real existing history, or no read date.
            manager.getLibraryManga(mangaId: identifier, context: context)?.lastRead = manager
                .getHistoryForManga(mangaId: identifier, context: context).compactMap(\.dateRead).max()
            if let category = AppSettings.library.defaultCategory.get(),
               manager.hasCategory(title: category, context: context) {
                manager.addCategoriesToManga(mangaId: identifier, categories: [category], context: context)
            }
            added.append(identifier)
        }
        if context.hasChanges { try context.save() }
        return .init(added: added, existing: existing)
    }

    private static func write(_ receipt: Receipt) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try FileManager.default.createDirectory(at: URL.documentsDirectory, withIntermediateDirectories: true)
            try encoder.encode(receipt).write(to: URL.documentsDirectory.appending(path: receiptName), options: .atomic)
        } catch {
            LogManager.logger.error("The personal import receipt could not be saved.")
        }
    }
}
#endif
