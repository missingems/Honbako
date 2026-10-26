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
        finishedReadingAt: Date? = nil
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
    }

    fileprivate func updating(manga: AidokuRunner.Manga, isInLibrary: Bool? = nil) -> Self {
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
            releaseYear: releaseYear,
            unreadChapterCount: unreadChapterCount,
            latestUnreadChapterDate: latestUnreadChapterDate,
            finishedReadingAt: finishedReadingAt
        )
    }

    fileprivate func applying(_ shelf: SumiLibraryShelfSummary) -> Self {
        Self(manga: manga, chapterLabel: chapterLabel, pageLabel: pageLabel, progress: progress,
             isInLibrary: isInLibrary, lastRead: lastRead, bookmark: bookmark,
             resumeDeviceLabel: resumeDeviceLabel, lastReadPage: lastReadPage,
             releaseDate: releaseDate, releaseYear: releaseYear,
             unreadChapterCount: shelf.unreadCount, latestUnreadChapterDate: shelf.latestUnreadDate,
             finishedReadingAt: shelf.finishedAt)
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
    @Published private(set) var library: [SumiBook] = []
    @Published private(set) var recentlyRead: [SumiBook] = []
    @Published private(set) var searchResults: [SumiBook] = []
    @Published private(set) var isSearching = false
    @Published private(set) var needsConnection = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var providerFailures: [String: String] = [:]

    private var searchEditions: [MangaIdentifier: [SumiBook]] = [:]
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

    init() {
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
            library = books.saved
            recentlyRead = books.recent
            libraryError = nil
            let snapshots = Dictionary((books.saved + books.recent).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            func enrich(_ book: SumiBook) -> SumiBook {
                snapshots[book.id].map { $0.updating(manga: SumiMangaMetadata.merging($0.manga, with: book.manga)) }
                    ?? SumiBook(manga: book.manga)
            }
            searchResults = searchResults.map(enrich)
            searchEditions = searchEditions.mapValues { $0.map(enrich) }
        } catch {
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            libraryError = "Your reading library could not be loaded: \(error.localizedDescription)"
        }
        updateErrorMessage()
    }

    func editions(for book: SumiBook) -> [SumiBook] {
        searchEditions[book.id] ?? [book]
    }

    func sourceName(for key: String) -> String { sourceNames[key] ?? key }

    /// Empty queries discover real catalog entries; typed queries search every enabled provider.
    func search(query: String) {
        cancelSearch()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let generation = searchGeneration
        searchEditions = [:]
        if query.isEmpty { searchResults = [] }
        else { setSearchResults([], query: query) }
        providerFailures = [:]
        searchError = nil
        isSearching = true
        updateErrorMessage()
        searchTask = Task { [weak self] in
            guard let self else { return }
            if !query.isEmpty {
                do { try await Task.sleep(nanoseconds: 350_000_000) }
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
        let loaded = await SourceManager.shared.getLoadedSources()
        guard !Task.isCancelled, generation == searchGeneration else { return }
        let sources = loaded.sorted { $0.key < $1.key }
        needsConnection = sources.isEmpty
        let byKey = Dictionary(sources.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        sourceNames = Dictionary(sources.map { ($0.key, $0.name) }, uniquingKeysWith: { first, _ in first })
        providerFailures = bootstrap.failures.filter { byKey[$0.key] == nil }
        guard !sources.isEmpty else {
            isSearching = false
            searchError = "Add a source in Connections to search for manga."
            updateErrorMessage()
            return
        }

        if query.isEmpty {
            for source in sources {
                let outcome = await Self.fetch(source: source, query: nil)
                guard !Task.isCancelled, generation == searchGeneration else { return }
                accept(outcome: outcome)
                if !searchResults.isEmpty { break }
            }
        } else {
            await withTaskGroup(of: ProviderOutcome.self) { group in
                var nextIndex = 0
                var resultsBySource: [String: [AidokuRunner.Manga]] = [:]
                for _ in 0..<min(3, sources.count) {
                    let source = sources[nextIndex]
                    nextIndex += 1
                    group.addTask { await Self.fetch(source: source, query: query) }
                }
                while let outcome = await group.next() {
                    guard !Task.isCancelled, generation == searchGeneration else {
                        group.cancelAll()
                        return
                    }
                    if nextIndex < sources.count {
                        let source = sources[nextIndex]
                        nextIndex += 1
                        group.addTask { await Self.fetch(source: source, query: query) }
                    }
                    if let error = outcome.error {
                        providerFailures[outcome.sourceKey] = "\(outcome.sourceName): \(error)"
                    } else {
                        resultsBySource[outcome.sourceKey] = outcome.entries
                    }
                    setSearchResults(sources.flatMap { resultsBySource[$0.key] ?? [] }, query: query)
                    updateErrorMessage()
                }
            }
        }
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
            let result: AidokuRunner.MangaPageResult
            if query == nil {
                let listings = try await source.getListings()
                if let listing = listings.first {
                    result = try await source.getMangaList(listing: listing, page: 1)
                } else {
                    result = try await source.getSearchMangaList(query: nil, page: 1, filters: [])
                }
            } else {
                result = try await source.getSearchMangaList(query: query, page: 1, filters: [])
            }
            return ProviderOutcome(sourceKey: source.key, sourceName: source.name, entries: result.entries, error: nil)
        } catch {
            return ProviderOutcome(sourceKey: source.key, sourceName: source.name, entries: [], error: error.localizedDescription)
        }
    }

    private func accept(outcome: ProviderOutcome) {
        if let error = outcome.error {
            providerFailures[outcome.sourceKey] = "\(outcome.sourceName): \(error)"
        } else {
            setSearchResults(outcome.entries)
        }
        updateErrorMessage()
    }

    private func setSearchResults(_ manga: [AidokuRunner.Manga], query: String? = nil) {
        let savedBooks = library + recentlyRead
        let saved = Dictionary(savedBooks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<MangaIdentifier> = []
        var books: [SumiBook] = manga.compactMap { entry in
            guard seen.insert(entry.identifier).inserted else { return nil }
            guard let existing = saved[entry.identifier] else { return SumiBook(manga: entry) }
            let merged = SumiMangaMetadata.merging(existing.manga, with: entry)
            return existing.updating(manga: merged)
        }
        if let query {
            let text = SumiSearchRanking.normalized(query)
            var localSeen = seen
            books += savedBooks.filter {
                localSeen.insert($0.id).inserted && !text.isEmpty && SumiSearchRanking.normalized($0.title).contains(text)
            }
        }
        let groups = SumiSearchRanking.groups(books, query: query ?? "")
        searchResults = groups.map(\.book)
        searchEditions = [:]
        for group in groups {
            for edition in group.editions { searchEditions[edition.id] = group.editions }
        }
    }

    private func replaceBook(_ book: SumiBook) {
        if let index = library.firstIndex(where: { $0.id == book.id }) { library[index] = book }
        if let index = searchResults.firstIndex(where: { $0.id == book.id }) { searchResults[index] = book }
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
