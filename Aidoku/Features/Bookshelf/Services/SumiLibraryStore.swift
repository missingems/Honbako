//
//  SumiLibraryStore.swift
//  Sumi
//

#if SUMI
import AidokuRunner
import Combine
import CoreData
import Foundation

/// A value snapshot; managed objects never leave their context's queue.
struct SumiBook: Identifiable, Hashable, Sendable {
    let manga: AidokuRunner.Manga
    let chapterLabel: String?
    let pageLabel: String?
    let progress: Double?
    let isInLibrary: Bool
    let lastRead: Date?
    let bookmark: SumiBookmarkSnapshot?
    let resumeDeviceLabel: String?
    let lastReadPage: Int?
    let releaseDate: Date?
    let releaseYear: Int?
    let unreadChapterCount: Int
    let latestUnreadChapterDate: Date?
    let finishedReadingAt: Date?
    let searchLanguages: SumiSearchLanguageInfo?

    var hasUnfinishedBookmark: Bool { bookmark != nil }

    var id: MangaIdentifier { manga.identifier }
    var sourceKey: String { manga.sourceKey }
    var title: String { manga.title }
    var author: String? {
        let names = manga.authors?.filter { !$0.isEmpty } ?? []
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }
    var releaseDateLabel: String? {
        if let releaseDate { return "Released \(releaseDate.formatted(date: .abbreviated, time: .omitted))" }
        if let releaseYear, (1...9999).contains(releaseYear) { return "Released \(releaseYear)" }
        return nil
    }
    var blurb: String? { manga.description }
    var coverURL: URL? { manga.cover.flatMap(URL.init(string:)) }

    init(
        manga: AidokuRunner.Manga,
        chapterLabel: String? = nil,
        pageLabel: String? = nil,
        progress: Double? = nil,
        isInLibrary: Bool = false,
        lastRead: Date? = nil,
        bookmark: SumiBookmarkSnapshot? = nil,
        resumeDeviceLabel: String? = nil,
        lastReadPage: Int? = nil,
        releaseDate: Date? = nil,
        releaseYear: Int? = nil,
        unreadChapterCount: Int = 0,
        latestUnreadChapterDate: Date? = nil,
        finishedReadingAt: Date? = nil,
        searchLanguages: SumiSearchLanguageInfo? = nil
    ) {
        self.manga = manga
        self.chapterLabel = chapterLabel
        self.pageLabel = pageLabel
        self.progress = progress
        self.isInLibrary = isInLibrary
        self.lastRead = lastRead
        self.bookmark = bookmark
        self.resumeDeviceLabel = resumeDeviceLabel
        self.lastReadPage = lastReadPage ?? bookmark?.page
        self.releaseDate = releaseDate
        self.releaseYear = releaseYear
        self.unreadChapterCount = max(0, unreadChapterCount)
        self.latestUnreadChapterDate = latestUnreadChapterDate
        self.finishedReadingAt = finishedReadingAt
        self.searchLanguages = searchLanguages
    }

    func updating(manga: AidokuRunner.Manga, isInLibrary: Bool? = nil,
                  releaseYear: Int? = nil, searchLanguages: SumiSearchLanguageInfo? = nil) -> Self {
        Self(
            manga: manga,
            chapterLabel: chapterLabel,
            pageLabel: pageLabel,
            progress: progress,
            isInLibrary: isInLibrary ?? self.isInLibrary,
            lastRead: lastRead,
            bookmark: bookmark,
            resumeDeviceLabel: resumeDeviceLabel,
            lastReadPage: lastReadPage,
            releaseDate: releaseDate,
            releaseYear: releaseYear ?? self.releaseYear,
            unreadChapterCount: unreadChapterCount,
            latestUnreadChapterDate: latestUnreadChapterDate,
            finishedReadingAt: finishedReadingAt,
            searchLanguages: searchLanguages ?? self.searchLanguages
        )
    }

    fileprivate func applying(_ shelf: SumiLibraryShelfSummary) -> Self {
        Self(manga: manga, chapterLabel: chapterLabel, pageLabel: pageLabel, progress: progress,
             isInLibrary: isInLibrary, lastRead: lastRead, bookmark: bookmark,
             resumeDeviceLabel: resumeDeviceLabel, lastReadPage: lastReadPage,
             releaseDate: releaseDate, releaseYear: releaseYear,
             unreadChapterCount: shelf.unreadCount, latestUnreadChapterDate: shelf.latestUnreadDate,
             finishedReadingAt: shelf.finishedAt, searchLanguages: searchLanguages)
    }

    fileprivate static func snapshot(manga: MangaObject, history: HistoryObject?, isInLibrary: Bool) -> Self {
        let chapter = history.flatMap { entry in
            entry.chapter ?? entry.managedObjectContext.flatMap {
                CoreDataManager.shared.getChapter(chapterId: entry.identifier, context: $0)
            }
        }?.toNewChapter()
        let page = history.map { Int($0.progress) }
        let total = history.map { Int($0.total) } ?? 0
        let completed = history?.completed ?? false
        let progress: Double?
        let pageLabel: String?
        if completed { progress = 1; pageLabel = "Completed" }
        else if let page, page > 0 {
            progress = total > 0 ? min(1, Double(page) / Double(total)) : nil
            pageLabel = total > 0 ? "Page \(page) of \(total)" : "Page \(page)"
        } else { progress = nil; pageLabel = nil }
        return SumiBook(manga: manga.toNewManga(), chapterLabel: chapterLabel(for: chapter),
            pageLabel: pageLabel, progress: progress, isInLibrary: isInLibrary,
            lastRead: history?.dateRead,
            bookmark: history.flatMap { SumiBookmarkSnapshot(chapterKey: $0.chapterId,
                page: Int($0.progress), completed: $0.completed) },
            resumeDeviceLabel: history.flatMap { SumiReadingProvenance.deviceLabel(for: $0) },
            lastReadPage: page.flatMap { $0 > 0 ? $0 : nil })
    }

    fileprivate static func chapterLabel(for chapter: AidokuRunner.Chapter?) -> String? {
        guard let chapter else { return nil }
        if let number = chapter.chapterNumber {
            return "Chapter \(String(format: "%g", Double(number)))"
        }
        if let title = chapter.title, !title.isEmpty { return title }
        if let number = chapter.volumeNumber {
            return "Volume \(String(format: "%g", Double(number)))"
        }
        return nil
    }
}

struct SumiReaderSelection: Identifiable {
    let id = UUID()
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    let chapter: AidokuRunner.Chapter
    /// Reader pages and persisted history are one-based.
    let startPage: Int?
}

@MainActor
final class SumiLibraryStore: ObservableObject {
    typealias SearchSourceLoader = @MainActor @Sendable () async -> [AidokuRunner.Source]
    typealias CoverPreparer = @Sendable ([SumiBook]) async -> Void
    @Published private(set) var library: [SumiBook] = []
    @Published private(set) var recentlyRead: [SumiBook] = []
    @Published private(set) var searchResults: [SumiBook] = []
    @Published private(set) var searchSections: [SumiSearchSourceSection] = []
    @Published private(set) var isSearching = false
    @Published private(set) var needsConnection = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var providerFailures: [String: String] = [:]

    private var searchEditions: [MangaIdentifier: [SumiBook]] = [:]
    private var preparedSearchBooks: [String: [SumiBook]] = [:]
    private var searchSourceOrder: [String] = []
    private var unavailableSearchSources: Set<String> = []
    private let searchSourceLoader: SearchSourceLoader
    private let searchPreparationService: SumiSearchPreparationService
    private let coverPreparer: CoverPreparer
    private var sourceNames: [String: String] = [:]
    private var searchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var refreshGeneration = 0
    private var loadingCount = 0
    private var mutatingBooks: Set<MangaIdentifier> = []
    private var libraryError: String?
    private var operationError: String?
    private var searchError: String?
    private var cancellables: Set<AnyCancellable> = []

    init(searchSourceLoader: SearchSourceLoader? = nil,
         searchPreparationService: SumiSearchPreparationService = .shared,
         coverPreparer: @escaping CoverPreparer = { await SumiCoverArtworkLoader.shared.prepare($0) }) {
        self.searchSourceLoader = searchSourceLoader ?? { await SourceManager.shared.getLoadedSources() }
        self.searchPreparationService = searchPreparationService
        self.coverPreparer = coverPreparer
        for name in [
            Notification.Name.updateLibrary,
            .updateMangaDetails,
            .updateHistory,
            .historyAdded,
            .historyRemoved,
            .historySet
        ] {
            NotificationCenter.default.publisher(for: name)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in self?.scheduleRefresh() }
                }
                .store(in: &cancellables)
        }
        NotificationCenter.default.publisher(for: .sourceUnloaded)
            .sink { [weak self] notification in
                guard let key = notification.object as? String else { return }
                Task { @MainActor [weak self] in self?.removeSearchSource(key) }
            }
            .store(in: &cancellables)
    }

    deinit {
        searchTask?.cancel()
        refreshTask?.cancel()
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        beginLoading()
        defer { endLoading() }
        do {
            let books = try await CoreDataManager.shared.container.performBackgroundTask { context in
                let request = LibraryMangaObject.fetchRequest()
                request.predicate = NSPredicate(format: "manga != nil")
                request.sortDescriptors = [NSSortDescriptor(key: "lastOpened", ascending: false)]
                let objects = try context.fetch(request)

                let historyRequest = HistoryObject.fetchRequest()
                historyRequest.sortDescriptors = [NSSortDescriptor(key: "dateRead", ascending: false)]
                let history = try context.fetch(historyRequest)
                var latestHistory: [MangaIdentifier: HistoryObject] = [:]
                for entry in history where latestHistory[entry.identifier.mangaIdentifier] == nil {
                    latestHistory[entry.identifier.mangaIdentifier] = entry
                }

                let chapterRequest = ChapterObject.fetchRequest()
                chapterRequest.predicate = NSPredicate(format: "manga.libraryObject != nil")
                chapterRequest.relationshipKeyPathsForPrefetching = ["history"]
                let allChapters = try context.fetch(chapterRequest)
                let chaptersByManga = Dictionary(grouping: allChapters) { $0.identifier.mangaIdentifier }

                var seen: Set<MangaIdentifier> = []
                let saved = objects.compactMap { object -> SumiBook? in
                    guard let manga = object.manga, seen.insert(manga.identifier).inserted else { return nil }
                    let filters = CoreDataManager.shared.getMangaChapterFilters(mangaId: manga.identifier, context: context)
                    let language = filters.language ?? latestHistory[manga.identifier]?.chapter?.lang
                    let chapters = (chaptersByManga[manga.identifier] ?? []).map {
                        SumiLibraryShelfSummary.Chapter(key: $0.id, number: $0.chapter?.doubleValue,
                            volume: $0.volume?.doubleValue, language: $0.lang, scanlator: $0.scanlator,
                            locked: $0.locked, uploaded: $0.dateUploaded,
                            completedAt: $0.history?.completed == true ? $0.history?.dateRead : nil)
                    }
                    let shelf = SumiLibraryShelfSummary(status: manga.toNewManga().status, chapters: chapters,
                        language: language, scanlators: filters.scanlators)
                    return SumiBook.snapshot(manga: manga, history: latestHistory[manga.identifier], isInLibrary: true)
                        .applying(shelf)
                }.sorted {
                    let lhs = $0.lastRead ?? .distantPast
                    let rhs = $1.lastRead ?? .distantPast
                    return lhs == rhs ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : lhs > rhs
                }
                let recent = latestHistory.compactMap { identifier, entry -> SumiBook? in
                    guard let manga = CoreDataManager.shared.getManga(mangaId: identifier, context: context) else { return nil }
                    return SumiBook.snapshot(manga: manga, history: entry, isInLibrary: seen.contains(identifier))
                }.sorted { ($0.lastRead ?? .distantPast) > ($1.lastRead ?? .distantPast) }
                return (saved: saved, recent: recent)
            }
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            await coverPreparer(books.saved)
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            library = books.saved
            recentlyRead = books.recent
            libraryError = nil
            let snapshots = Dictionary((books.saved + books.recent).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            func enrich(_ book: SumiBook) -> SumiBook {
                snapshots[book.id].map { $0.updating(manga: SumiMangaMetadata.merging($0.manga, with: book.manga),
                    releaseYear: book.releaseYear, searchLanguages: book.searchLanguages) } ?? book
            }
            searchResults = searchResults.map(enrich)
            searchEditions = searchEditions.mapValues { $0.map(enrich) }
            updateSearchSections()
        } catch {
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            libraryError = "Your reading library could not be loaded: \(error.localizedDescription)"
        }
        updateErrorMessage()
    }

    func editions(for book: SumiBook) -> [SumiBook] {
        searchEditions[book.id] ?? [book]
    }

    func sourceName(for key: String) -> String {
        SourceStore.shared.source(for: key)?.name ?? sourceNames[key] ?? key
    }

    /// Empty queries discover real catalog entries; typed queries search every enabled provider.
    func search(query: String) {
        cancelSearch()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let generation = searchGeneration
        searchEditions = [:]
        searchResults = []
        searchSections = []
        preparedSearchBooks = [:]
        searchSourceOrder = []
        unavailableSearchSources = []
        providerFailures = [:]
        searchError = nil
        isSearching = true
        updateErrorMessage()
        searchTask = Task { [weak self] in
            guard let self else { return }
            if !query.isEmpty {
                do { try await Task.sleep(for: .milliseconds(200)) }
                catch { return }
            }
            guard !Task.isCancelled, generation == self.searchGeneration else { return }
            await self.performSearch(query: query, generation: generation)
        }
    }

    func cancelSearch() {
        searchGeneration += 1
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    func fetchDetails(for book: SumiBook) async -> SumiBook {
        beginLoading()
        operationError = nil
        updateErrorMessage()
        defer { endLoading() }
        guard let source = await SourceManager.shared.source(for: book.sourceKey) else {
            operationError = "This title's source is currently unavailable."
            updateErrorMessage()
            return book
        }
        do {
            let persisted = await CoreDataManager.shared.container.performBackgroundTask { context in
                let manager = CoreDataManager.shared
                return (manager.getManga(mangaId: book.id, context: context)?.toNewManga(),
                        manager.getMangaChapterFilters(mangaId: book.id, context: context).language)
            }
            let original = persisted.0 ?? book.manga
            let fetched = try await SumiLanguageChapterLoader.update(source: source, manga: original,
                needsDetails: true, preferredLanguage: persisted.1)
            try Task.checkCancellation()
            guard fetched.identifier == book.id else {
                throw StoreError.mismatchedTitle
            }
            let manga = SumiMangaMetadata.merging(original, with: fetched)
            try await CoreDataManager.shared.container.performBackgroundTask { context in
                guard let object = CoreDataManager.shared.getLibraryManga(mangaId: book.id, context: context)?.manga else { return }
                object.load(from: manga)
                if let chapters = manga.chapters {
                    CoreDataManager.shared.setChapters(chapters, mangaId: book.id, context: context)
                }
                try context.save()
            }
            let updated = (library.first { $0.id == book.id } ?? book).updating(manga: manga)
            replaceBook(updated)
            return updated
        } catch is CancellationError {
            return book
        } catch {
            operationError = "Title details could not be loaded: \(error.localizedDescription)"
            updateErrorMessage()
            return book
        }
    }

    func add(book: SumiBook) async {
        guard mutatingBooks.insert(book.id).inserted else { return }
        defer { mutatingBooks.remove(book.id) }
        let alreadySaved = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.hasLibraryManga(mangaId: book.id, context: context)
        }
        guard !alreadySaved else { await refresh(); return }
        // Direct opening has already fetched the complete chapter metadata.
        // Persist that prepared snapshot instead of repeating the same requests.
        let detailed: SumiBook
        if book.manga.chapters?.isEmpty == false { detailed = book }
        else { detailed = await fetchDetails(for: book) }
        guard !Task.isCancelled else { return }
        beginLoading()
        defer { endLoading() }
        await MangaManager.shared.addToLibrary(manga: detailed.manga, chapters: detailed.manga.chapters ?? [])
        await HonbakoChapterAlerts.shared.didAddToLibrary(book.id)
        await refresh()
    }

    func remove(book: SumiBook) async {
        guard mutatingBooks.insert(book.id).inserted else { return }
        defer { mutatingBooks.remove(book.id) }
        beginLoading()
        defer { endLoading() }
        await MangaManager.shared.removeFromLibrary(mangaIds: [book.id])
        await refresh()
    }

    /// The grid opens the latest actual history action, including completed
    /// chapters. A new reader gets the first readable real chapter plus a
    /// presentation-only front-matter flag; no synthetic progress is stored.
    func prepareReader(book: SumiBook) async -> SumiReaderOpening? {
        beginLoading()
        operationError = nil
        updateErrorMessage()
        defer { endLoading() }
        do {
            await SumiCatalogBootstrap.shared.prepare()
            try Task.checkCancellation()
            let preferredLanguage = SumiChapterLanguage.persistedLanguage(mangaID: book.id)
            let initialHistory = try await latestReaderHistory(for: book)
            var detailed = book
            if detailed.manga.viewer == .unknown {
                let storedViewer = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.getManga(mangaId: book.id, context: context)?.toNewManga().viewer
                }
                if let storedViewer, storedViewer != .unknown {
                    var manga = detailed.manga
                    manga.viewer = storedViewer
                    detailed = detailed.updating(manga: manga)
                }
            }
            var stored = await MangaManager.shared.getNextChapter(mangaId: book.id, fallbackChapters: detailed.manga.chapters)
            try Task.checkCancellation()
            let missingSavedChapter = initialHistory.map { history in
                !stored.chapters.contains { $0.key == history.chapterKey }
            } ?? false
            let missingPreferredLanguage = initialHistory == nil && SumiChapterLanguage.normalized(preferredLanguage) != nil
                && SumiChapterLanguage.filter(stored.chapters, language: preferredLanguage).isEmpty
            if stored.chapters.isEmpty || missingSavedChapter || missingPreferredLanguage
                || (initialHistory == nil && detailed.manga.viewer == .unknown) {
                detailed = await fetchDetails(for: detailed)
                try Task.checkCancellation()
                stored = await MangaManager.shared.getNextChapter(mangaId: book.id, fallbackChapters: detailed.manga.chapters)
            }
            let source = await SourceManager.shared.source(for: book.sourceKey)
            let ascending = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.getMangaChapterFilters(mangaId: book.id, context: context).flags
                    & ChapterFlagMask.sortAscending != 0
            }
            try Task.checkCancellation()
            let chapters = ascending ? Array(stored.chapters.reversed()) : stored.chapters
            var manga = detailed.manga
            manga.chapters = chapters
            if !AppSettings.general.incognitoMode.get() {
                let preparedManga = manga
                try await CoreDataManager.shared.container.performBackgroundTask { context in
                    let manager = CoreDataManager.shared
                    manager.getOrCreateManga(preparedManga, context: context).load(from: preparedManga)
                    manager.setChapters(chapters, mangaId: book.id, context: context)
                    try context.save()
                }
            }
            // Refresh after metadata/network awaits: imported progress can have
            // changed while the title was loading.
            let latestHistory = try await latestReaderHistory(for: book)
            try Task.checkCancellation()
            let firstLanguage = SumiChapterLanguage.normalized(preferredLanguage)
                ?? SumiChapterLanguage.activeLanguage(chapters: chapters, currentChapter: nil, preferred: nil)
            let eligibleChapters = latestHistory == nil ? SumiChapterLanguage.filter(chapters, language: firstLanguage) : chapters
            let choice = SumiReaderOpeningPolicy.choose(history: latestHistory, chaptersNewestFirst: eligibleChapters) { chapter in
                let id = ChapterIdentifier(sourceKey: book.sourceKey, mangaKey: book.manga.key, chapterKey: chapter.key)
                return DownloadManager.shared.getDownloadStatus(for: id) == .finished || (source != nil && !chapter.locked)
            }
            guard let choice else {
                if latestHistory == nil && chapters.isEmpty && operationError != nil {
                    updateErrorMessage()
                    return nil
                }
                operationError = latestHistory == nil
                    ? "No readable chapters are available for this title."
                    : "Your last-read chapter is unavailable. It has not been replaced with another chapter."
                updateErrorMessage()
                return nil
            }
            guard let chapter = chapters.first(where: { $0.key == choice.chapterKey }) else {
                return nil
            }
            try Task.checkCancellation()
            // Metadata, source availability and chapters were already resolved
            // above. Re-entering selectChapter repeats all those database reads
            // and can issue the same chapter request again for unsaved manga.
            let exactSelection = SumiReaderSelection(source: source, manga: manga,
                                                     chapter: chapter, startPage: choice.startPage)
            return SumiReaderOpening(selection: exactSelection, isFirstRead: choice.isFirstRead)
        } catch is CancellationError {
            return nil
        } catch {
            operationError = "Your reading position could not be loaded: \(error.localizedDescription)"
            updateErrorMessage()
            return nil
        }
    }

    private func latestReaderHistory(for book: SumiBook) async throws -> SumiReaderHistorySnapshot? {
        try await CoreDataManager.shared.container.performBackgroundTask { context in
            let request = HistoryObject.fetchRequest()
            request.predicate = NSPredicate(format: "mangaId == %@ AND sourceId == %@", book.manga.key, book.sourceKey)
            request.sortDescriptors = [NSSortDescriptor(key: "dateRead", ascending: false)]
            request.fetchLimit = 1
            guard let entry = try context.fetch(request).first else { return SumiReaderHistorySnapshot?.none }
            return SumiReaderHistorySnapshot(chapterKey: entry.chapterId, page: Int(entry.progress), completed: entry.completed)
        }
    }

    func resume(book: SumiBook) async -> SumiReaderSelection? {
        beginLoading()
        operationError = nil
        updateErrorMessage()
        defer { endLoading() }
        let source = await SourceManager.shared.source(for: book.sourceKey)
        var manga = book.manga
        var stored = await MangaManager.shared.getNextChapter(mangaId: book.id, fallbackChapters: manga.chapters)
        if stored.chapters.isEmpty, let source {
            do {
                let fetched = try await source.getMangaUpdate(manga: manga, needsDetails: false, needsChapters: true)
                try Task.checkCancellation()
                guard fetched.identifier == book.id else { throw StoreError.mismatchedTitle }
                manga = SumiMangaMetadata.merging(manga, with: fetched)
                stored = await MangaManager.shared.getNextChapter(mangaId: book.id, fallbackChapters: manga.chapters)
            } catch is CancellationError {
                return nil
            } catch {
                operationError = "Chapters could not be loaded: \(error.localizedDescription)"
                updateErrorMessage()
                return nil
            }
        }
        guard !Task.isCancelled else { return nil }
        let sortAscending = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getMangaChapterFilters(mangaId: book.id, context: context).flags
                & ChapterFlagMask.sortAscending != 0
        }
        // The canonical reader advances toward the preceding item in a newest-first list.
        let readerChapters = sortAscending ? Array(stored.chapters.reversed()) : stored.chapters
        let canRead: (AidokuRunner.Chapter) -> Bool = { chapter in
            let id = ChapterIdentifier(sourceKey: book.sourceKey, mangaKey: manga.key, chapterKey: chapter.key)
            let downloaded = DownloadManager.shared.getDownloadStatus(for: id) == .finished
            return downloaded || (source != nil && !chapter.locked)
        }
        let resumingChapter = stored.nextChapter.flatMap { canRead($0) ? $0 : nil }
        let rereading = stored.nextChapter == nil
        guard let chapter = resumingChapter ?? readerChapters.reversed().first(where: canRead) else {
            operationError = source == nil
                ? "This title's source is unavailable and no readable chapter has been downloaded."
                : "No readable chapters are available for this title."
            updateErrorMessage()
            return nil
        }
        let history = await CoreDataManager.shared.getReadingHistory(mangaId: book.id)
        let page = history[chapter.key]?.page
        manga.chapters = readerChapters
        if !AppSettings.general.incognitoMode.get() {
            await CoreDataManager.shared.setOpened(mangaId: book.id)
        }
        guard !Task.isCancelled else { return nil }
        let startPage = rereading ? 1 : page.flatMap { $0 > 0 ? $0 : nil }
        return SumiReaderSelection(source: source, manga: manga, chapter: chapter, startPage: startPage)
    }

    /// Opens only the latest unfinished history's exact chapter. Unlike normal
    /// resume, a removed or locked bookmark must never fall back to another one.
    func openBookmark(book: SumiBook) async -> SumiReaderSelection? {
        beginLoading()
        operationError = nil
        updateErrorMessage()
        defer { endLoading() }
        do {
            let bookmark = try await CoreDataManager.shared.container.performBackgroundTask { context in
                let request = HistoryObject.fetchRequest()
                request.predicate = NSPredicate(format: "mangaId == %@ AND sourceId == %@", book.manga.key, book.sourceKey)
                request.sortDescriptors = [NSSortDescriptor(key: "dateRead", ascending: false)]
                request.fetchLimit = 1
                guard let entry = try context.fetch(request).first else { return SumiBookmarkSnapshot?.none }
                return SumiBookmarkSnapshot(chapterKey: entry.chapterId, page: Int(entry.progress), completed: entry.completed)
            }
            guard !Task.isCancelled else { return nil }
            guard let bookmark else {
                operationError = "No unfinished bookmark is available. Choose a chapter or continue reading."
                updateErrorMessage()
                return nil
            }
            return await selectChapter(book: book, chapter: AidokuRunner.Chapter(key: bookmark.chapterKey))
        } catch {
            guard !Task.isCancelled else { return nil }
            operationError = "Your bookmark could not be loaded: \(error.localizedDescription)"
            updateErrorMessage()
            return nil
        }
    }

    func chapterSnapshots(for book: SumiBook) async -> [SumiChapterSnapshot] {
        let stored = await MangaManager.shared.getNextChapter(mangaId: book.id, fallbackChapters: book.manga.chapters)
        guard !Task.isCancelled else { return [] }
        let history = await CoreDataManager.shared.container.performBackgroundTask { context in
            let entries = CoreDataManager.shared.getHistoryForManga(mangaId: book.id, context: context).sorted {
                ($0.dateRead ?? .distantPast) > ($1.dateRead ?? .distantPast)
            }
            var result: [String: (page: Int, total: Int, completed: Bool)] = [:]
            for entry in entries where result[entry.chapterId] == nil {
                result[entry.chapterId] = (Int(entry.progress), Int(entry.total), entry.completed)
            }
            return result
        }
        let sourceAvailable = await SourceManager.shared.source(for: book.sourceKey) != nil
        guard !Task.isCancelled else { return [] }
        var seen: Set<String> = []
        return stored.chapters.compactMap { chapter in
            guard seen.insert(chapter.key).inserted else { return nil }
            let id = ChapterIdentifier(sourceKey: book.sourceKey, mangaKey: book.manga.key, chapterKey: chapter.key)
            let state = history[chapter.key]
            let completed = state?.completed ?? false
            let page = state.flatMap { $0.page > 0 && !completed ? $0.page : nil }
            let total = state.flatMap { $0.total > 0 ? $0.total : nil }
            let downloaded = DownloadManager.shared.getDownloadStatus(for: id) == .finished
            return SumiChapterSnapshot(
                id: id, chapter: chapter, completed: completed,
                currentPage: page, totalPages: total,
                isCurrent: stored.nextChapter?.key == chapter.key,
                canRead: downloaded || (sourceAvailable && !chapter.locked)
            )
        }
    }

    /// Explicit chapter selection never falls back to a different chapter. Saved
    /// unfinished progress is resumed; a completed chapter is reread from page 1.
    func selectChapter(book: SumiBook, chapter selectedChapter: AidokuRunner.Chapter) async -> SumiReaderSelection? {
        beginLoading()
        operationError = nil
        updateErrorMessage()
        defer { endLoading() }
        let source = await SourceManager.shared.source(for: book.sourceKey)
        var manga = book.manga
        var stored = await MangaManager.shared.getNextChapter(mangaId: book.id, fallbackChapters: manga.chapters)
        if stored.chapters.isEmpty, let source {
            do {
                let fetched = try await source.getMangaUpdate(manga: manga, needsDetails: false, needsChapters: true)
                try Task.checkCancellation()
                guard fetched.identifier == book.id else { throw StoreError.mismatchedTitle }
                manga = SumiMangaMetadata.merging(manga, with: fetched)
                stored = await MangaManager.shared.getNextChapter(mangaId: book.id, fallbackChapters: manga.chapters)
            } catch is CancellationError {
                return nil
            } catch {
                operationError = "Chapters could not be loaded: \(error.localizedDescription)"
                updateErrorMessage()
                return nil
            }
        }
        guard !Task.isCancelled else { return nil }
        let sortAscending = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.getMangaChapterFilters(mangaId: book.id, context: context).flags
                & ChapterFlagMask.sortAscending != 0
        }
        let readerChapters = sortAscending ? Array(stored.chapters.reversed()) : stored.chapters
        guard let chapter = readerChapters.first(where: { $0.key == selectedChapter.key }) else {
            operationError = "This chapter is no longer available. Reload the chapter list and try again."
            updateErrorMessage()
            return nil
        }
        let id = ChapterIdentifier(sourceKey: book.sourceKey, mangaKey: manga.key, chapterKey: chapter.key)
        let downloaded = DownloadManager.shared.getDownloadStatus(for: id) == .finished
        guard downloaded || (source != nil && !chapter.locked) else {
            operationError = "This chapter is unavailable from this provider and has not been downloaded."
            updateErrorMessage()
            return nil
        }
        let history = await CoreDataManager.shared.getReadingHistory(mangaId: book.id)
        guard !Task.isCancelled else { return nil }
        manga.chapters = readerChapters
        if !AppSettings.general.incognitoMode.get() {
            // Reading retains metadata and history without changing collection
            // membership. Only the explicit Add action saves a library entry.
            do {
                let preparedManga = manga
                try await CoreDataManager.shared.container.performBackgroundTask { context in
                    let manager = CoreDataManager.shared
                    manager.getOrCreateManga(preparedManga, context: context).load(from: preparedManga)
                    manager.setChapters(readerChapters, mangaId: book.id, context: context)
                    try context.save()
                }
            } catch {
                operationError = "This manga’s reading position couldn’t be prepared. Try again."
                updateErrorMessage()
                return nil
            }
            await CoreDataManager.shared.setOpened(mangaId: book.id)
        }
        guard !Task.isCancelled else { return nil }
        let page = history[chapter.key]?.page
        let startPage = page.flatMap { $0 > 0 ? $0 : nil } ?? 1
        return SumiReaderSelection(source: source, manga: manga, chapter: chapter, startPage: startPage)
    }

    private func performSearch(query: String, generation: Int) async {
        let bootstrap = SumiCatalogBootstrap.shared
        #if SUMI && DEBUG
        defer {
            if generation == searchGeneration {
                var resultCountsByProvider: [String: Int] = [:]
                for key in bootstrap.availableSourceKeys { resultCountsByProvider[key] = 0 }
                for book in searchResults { resultCountsByProvider[book.sourceKey, default: 0] += 1 }
                SumiCatalogDiagnostics.write(
                    availableSourceKeys: bootstrap.availableSourceKeys,
                    providerFailures: providerFailures,
                    searchResultCount: searchResults.count,
                    resultCountsByProvider: resultCountsByProvider,
                    searchRunning: isSearching,
                    redactingSearchText: query
                )
            }
        }
        #endif
        await bootstrap.prepare()
        guard !Task.isCancelled, generation == searchGeneration else { return }
        let loaded = await searchSourceLoader()
        guard !Task.isCancelled, generation == searchGeneration else { return }
        let sources = loaded.filter { !unavailableSearchSources.contains($0.key) }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.key < $1.key : order == .orderedAscending
        }
        needsConnection = sources.isEmpty
        let byKey = Dictionary(sources.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        sourceNames = Dictionary(sources.map { ($0.key, $0.name) }, uniquingKeysWith: { first, _ in first })
        providerFailures = bootstrap.failures.filter { byKey[$0.key] == nil }
        guard !sources.isEmpty else {
            isSearching = false
            searchError = "Add a source in Settings to search for manga."
            updateErrorMessage()
            return
        }

        await SumiSourceSearchPipeline.run(sourceKeys: sources.map(\.key), fetch: { key in
            guard let source = byKey[key] else {
                return ProviderOutcome(sourceKey: key, sourceName: key, entries: [], error: "Source unavailable.")
            }
            return await Self.fetch(source: source, query: query.isEmpty ? nil : query)
        }, prepare: { [weak self] outcome in
            await self?.prepareSourceResults(outcome, sources: byKey, query: query, generation: generation)
        })
        guard !Task.isCancelled, generation == searchGeneration else { return }
        isSearching = false
        updateErrorMessage()
    }

    private struct ProviderOutcome: Sendable {
        let sourceKey: String
        let sourceName: String
        let entries: [AidokuRunner.Manga]
        let error: String?
    }

    nonisolated private static func fetch(source: AidokuRunner.Source, query: String?) async -> ProviderOutcome {
        do {
            let entries = try await SumiSearchProviderCache.shared.entries(source: source, query: query)
            return ProviderOutcome(sourceKey: source.key, sourceName: source.name, entries: entries, error: nil)
        } catch {
            return ProviderOutcome(sourceKey: source.key, sourceName: source.name, entries: [], error: error.localizedDescription)
        }
    }

    private func searchCandidates(_ manga: [AidokuRunner.Manga], sourceKey: String, query: String) -> [SumiBook] {
        let savedBooks = library + recentlyRead
        let saved = Dictionary(savedBooks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<MangaIdentifier> = []
        var books: [SumiBook] = manga.compactMap { entry in
            guard entry.sourceKey == sourceKey, seen.insert(entry.identifier).inserted else { return nil }
            guard let existing = saved[entry.identifier] else { return SumiBook(manga: entry) }
            let merged = SumiMangaMetadata.merging(existing.manga, with: entry)
            return existing.updating(manga: merged)
        }
        if !query.isEmpty {
            let text = SumiSearchRanking.normalized(query)
            var localSeen = seen
            books += savedBooks.filter {
                $0.sourceKey == sourceKey && localSeen.insert($0.id).inserted && !text.isEmpty
                    && SumiSearchRanking.normalized($0.title).contains(text)
            }
        }
        return SumiSearchRanking.groups(books, query: query).flatMap(\.editions)
    }

    private func prepareSourceResults(_ result: ProviderOutcome, sources: [String: AidokuRunner.Source],
                                      query: String, generation: Int) async {
        guard !Task.isCancelled, generation == searchGeneration,
              !unavailableSearchSources.contains(result.sourceKey) else { return }
        if let error = result.error {
            providerFailures[result.sourceKey] = "\(result.sourceName): \(error)"
            updateErrorMessage()
        }
        let candidates = searchCandidates(result.entries, sourceKey: result.sourceKey, query: query)
        do {
            let outcome = try await searchPreparationService.prepare(candidates, sources: sources)
            try Task.checkCancellation()
            await coverPreparer(outcome.books)
            guard !Task.isCancelled, generation == searchGeneration,
                  !unavailableSearchSources.contains(result.sourceKey) else { return }
            for key in outcome.failedSourceKeys where providerFailures[key] == nil {
                providerFailures[key] = "\(sourceName(for: key)): Chapter availability couldn’t be checked."
            }
            publishPreparedSearchResults(outcome.books, sourceKey: result.sourceKey, query: query)
            updateErrorMessage()
        } catch {
            // Cancellation supersedes the entire section, never a partial row
            // snapshot left behind from the previous query.
            return
        }
    }

    private func publishPreparedSearchResults(_ books: [SumiBook], sourceKey: String, query: String) {
        let snapshots = Dictionary((library + recentlyRead).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let current = books.map { book in
            snapshots[book.id].map { snapshot in
                snapshot.updating(manga: SumiMangaMetadata.merging(snapshot.manga, with: book.manga),
                    releaseYear: book.releaseYear, searchLanguages: book.searchLanguages)
            } ?? book
        }
        let previous = preparedSearchBooks[sourceKey]?.map(\.id) ?? []
        preparedSearchBooks[sourceKey] = SumiSearchRanking.stableGroups(current, query: query,
            previouslyPublished: previous).map(\.book)
        if !current.isEmpty, !searchSourceOrder.contains(sourceKey) { searchSourceOrder.append(sourceKey) }
        searchResults = searchSourceOrder.flatMap { preparedSearchBooks[$0] ?? [] }
        searchEditions = Dictionary(searchResults.map { ($0.id, [$0]) }, uniquingKeysWith: { first, _ in first })
        updateSearchSections()
    }

    private func updateSearchSections() {
        searchSections = SumiSearchSourceSection.grouping(searchResults, sourceName: sourceName(for:))
    }

    private func removeSearchSource(_ key: String) {
        unavailableSearchSources.insert(key)
        preparedSearchBooks[key] = nil
        searchSourceOrder.removeAll { $0 == key }
        searchResults.removeAll { $0.sourceKey == key }
        searchEditions = searchEditions.filter { $0.key.sourceKey != key }
        providerFailures[key] = nil
        updateSearchSections()
        updateErrorMessage()
    }

    private func replaceBook(_ book: SumiBook) {
        if let index = library.firstIndex(where: { $0.id == book.id }) { library[index] = book }
        if let index = searchResults.firstIndex(where: { $0.id == book.id }) { searchResults[index] = book }
        updateSearchSections()
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 120_000_000) }
            catch { return }
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func beginLoading() {
        loadingCount += 1
        isLoading = true
    }

    private func endLoading() {
        loadingCount = max(0, loadingCount - 1)
        isLoading = loadingCount > 0
    }

    private func updateErrorMessage() {
        var messages = [libraryError, operationError, searchError].compactMap { $0 }
        if !providerFailures.isEmpty {
            messages.append(searchResults.isEmpty
                ? "Sources couldn’t be reached. Check your connection and try again."
                : "Some sources couldn’t be searched.")
        }
        errorMessage = messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    private enum StoreError: LocalizedError {
        case mismatchedTitle
        var errorDescription: String? { "The source returned a different title." }
    }
}
#endif
