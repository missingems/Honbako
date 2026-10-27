#if SUMI
import AidokuRunner
import Combine
import Foundation

/// One live queue snapshot feeds the chapter rows and the overall download UI.
@MainActor
final class HonbakoReaderChapterState: ObservableObject {
    @Published private(set) var reading: [String: HonbakoChapterReadingProgress] = [:]
    @Published private(set) var downloads: [String: Download] = [:]
    @Published private(set) var statuses: [String: DownloadStatus] = [:]
    private var mangaID: MangaIdentifier?
    private var chapterKeys: Set<String> = []
    private var observers: Set<AnyCancellable> = []
    private var currentKey = ""
    private var currentPage = 0
    private var currentTotal = 0
    private var generation = 0

    var activeDownloads: [Download] {
        downloads.values.filter { [.queued, .downloading, .paused].contains($0.status) }
            .sorted { $0.chapter.key < $1.chapter.key }
    }
    var failedCount: Int { statuses.values.filter { $0 == .failed }.count }
    var completedCount: Int { statuses.values.filter { $0 == .finished }.count }
    var hasCopies: Bool { statuses.values.contains { $0 == .finished || $0 == .failed } }
    var progress: Double? {
        guard !activeDownloads.isEmpty, !downloads.isEmpty else { return nil }
        // Chapters are the batch units; queued chapters need no speculative
        // network page-list request just to make overall progress accurate.
        let units = downloads.values.reduce(0.0) { result, item in
            if item.status == .finished { return result + 1 }
            guard item.status != .failed, item.total > 0 else { return result }
            return result + min(1, max(0, Double(item.progress) / Double(item.total)))
        }
        return units / Double(downloads.count)
    }

    init(mangaID: MangaIdentifier? = nil, chapterKeys: Set<String> = []) {
        self.mangaID = mangaID
        self.chapterKeys = chapterKeys
        for name in [Notification.Name.downloadProgressed, .downloadFinished, .downloadFailed, .downloadCancelled] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] notification in
                guard let download = notification.object as? Download else { return }
                Task { @MainActor [weak self] in self?.apply(download) }
            }.store(in: &observers)
        }
        NotificationCenter.default.publisher(for: .downloadsQueued).sink { [weak self] notification in
            guard let downloads = notification.object as? [Download] else { return }
            Task { @MainActor [weak self] in downloads.forEach { self?.apply($0) } }
        }.store(in: &observers)
        for name in [Notification.Name.downloadsRemoved, .downloadRemoved, .downloadsCancelled,
                     .downloadsPaused, .downloadsResumed, .updateHistory, .historyAdded, .historySet] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refresh() }
            }.store(in: &observers)
        }
    }

    func configure(manga: AidokuRunner.Manga?, chapters: [AidokuRunner.Chapter],
                   currentKey: String, currentPage: Int, currentTotal: Int) async {
        mangaID = manga?.identifier
        chapterKeys = Set(chapters.map(\.key))
        self.currentKey = currentKey
        self.currentPage = currentPage
        self.currentTotal = currentTotal
        await refresh()
    }

    func refresh() async {
        guard let mangaID else { return }
        generation += 1
        let request = generation
        let history = await Self.history(for: mangaID)
        let queue = await DownloadManager.shared.getDownloadQueue()[mangaID.sourceKey] ?? []
        guard request == generation, self.mangaID == mangaID else { return }
        reading = history
        if currentPage > 0 || currentTotal > 0 {
            reading[currentKey] = .init(page: currentPage, total: currentTotal,
                completed: currentTotal > 0 && currentPage >= currentTotal)
        }
        var states: [String: DownloadStatus] = [:]
        for key in chapterKeys {
            states[key] = DownloadManager.shared.getDownloadStatus(for: .init(sourceKey: mangaID.sourceKey,
                mangaKey: mangaID.mangaKey, chapterKey: key))
        }
        var next = activeDownloads.isEmpty ? [:] : downloads.filter {
            $0.value.status == .finished && states[$0.key] == .finished
        }
        for download in queue where download.mangaIdentifier == mangaID && chapterKeys.contains(download.chapter.key) {
            next[download.chapter.key] = download
            states[download.chapter.key] = download.status
        }
        downloads = next
        statuses = states
    }

    func apply(_ download: Download) {
        guard download.mangaIdentifier == mangaID, chapterKeys.contains(download.chapter.key) else { return }
        if download.status == .downloading, [.finished, .failed].contains(statuses[download.chapter.key] ?? .none) {
            return
        }
        if [.queued, .downloading].contains(download.status), activeDownloads.isEmpty,
           downloads[download.chapter.key] == nil { downloads = [:] }
        statuses[download.chapter.key] = download.status
        if download.status == .cancelled || download.status == .none { downloads[download.chapter.key] = nil }
        else { downloads[download.chapter.key] = download }
        if download.total > 0, reading[download.chapter.key]?.total ?? 0 == 0 {
            var value = reading[download.chapter.key] ?? .init()
            value.total = download.total
            reading[download.chapter.key] = value
        }
    }

    func completedKeys() async -> Set<String> {
        guard let mangaID else { return [] }
        let history = await Self.history(for: mangaID)
        return Set(history.filter { $0.value.completed }.map(\.key))
    }

    private static func history(for id: MangaIdentifier) async -> [String: HonbakoChapterReadingProgress] {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            Dictionary(CoreDataManager.shared.getHistoryForManga(mangaId: id, context: context).map {
                ($0.chapterId, HonbakoChapterReadingProgress(page: Int($0.progress), total: Int($0.total), completed: $0.completed))
            }, uniquingKeysWith: { first, _ in first })
        }
    }
}
#endif
