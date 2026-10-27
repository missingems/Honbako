//
//  DownloadQueue.swift
//  Aidoku
//
//  Created by Skitty on 5/13/22.
//

import AidokuRunner
@preconcurrency import BackgroundTasks
import Foundation

// stores queued and active downloads
// creates a downloadtask for every source
// only one chapter per source is downloaded at a time
actor DownloadQueue {
    private let cache: DownloadCache
    private let sourceLookup: DownloadTask.SourceLookup
    private var onCompletion: (() -> Void)?

    private(set) var queue: [String: [Download]] = [:] // all queued downloads stored under source id
    private(set) var tasks: [String: DownloadTask] = [:] // current worker identities for each source
    private var progressBlocks: [ChapterIdentifier: (Int, Int) -> Void] = [:]

    private var paused = false
    private var registeredTask = false
    private var backgroundTaskRequested = false
    private var totalDownloads: Int = 0
    private var completedDownloads: Int = 0
    private var bgTask: ProgressReporting?
    private var sendCancelNotification = true

    private static let taskIdentifier = (Bundle.main.bundleIdentifier ?? "") + ".download"

    init(cache: DownloadCache, onCompletion: (() -> Void)? = nil,
         sourceLookup: @escaping DownloadTask.SourceLookup = { await SourceManager.shared.source(for: $0) }) {
        self.cache = cache
        self.sourceLookup = sourceLookup
        self.onCompletion = onCompletion
    }

    func setOnCompletion(_ onCompletion: (() -> Void)?) {
        self.onCompletion = onCompletion
    }

    func start() async {
        paused = false

        guard !queue.isEmpty else { return }

#if !targetEnvironment(simulator)
        if
            bgTask == nil, !backgroundTaskRequested,
            #available(iOS 26.0, *),
            AppSettings.downloads.background.get(),
            !ProcessInfo.processInfo.isMacCatalystApp
        {
            await register()

            let request = BGContinuedProcessingTaskRequest(
                identifier: Self.taskIdentifier,
                title: NSLocalizedString("DOWNLOADING"),
                subtitle: NSLocalizedString("PROCESSING_QUEUE")
            )
            do {
                try await BGTaskScheduler.shared.submit(request: request)
                backgroundTaskRequested = true
            } catch {
                LogManager.logger.error("Failed to start background downloading: \(error)")
            }
        }
#endif

        // User-initiated work starts now. Continued processing extends it;
        // waiting for the scheduler first left the foreground queue idle.
        await initAndResumeTasks()
    }

    private func initAndResumeTasks() async {
        for (sourceKey, downloads) in queue {
            if tasks[sourceKey] == nil {
                let task = DownloadTask(id: sourceKey, cache: cache, downloads: downloads, sourceLookup: sourceLookup)
                await task.setDelegate(delegate: self)
                tasks[sourceKey] = task
            }
            await tasks[sourceKey]?.resume()
        }
    }

    func resume() async {
        paused = false

        if #available(iOS 26.0, *), AppSettings.downloads.background.get() {
            if bgTask == nil {
                await start()
            }
        }

        await withTaskGroup(of: Void.self) { group in
            for task in tasks.values {
                group.addTask { await task.resume() }
            }
        }
    }

    func pause() async {
        paused = true

        if #available(iOS 26.0, *) {
            if let task = bgTask as? BGContinuedProcessingTask {
                task.updateTitle(
                    NSLocalizedString("DOWNLOADING"),
                    subtitle: NSLocalizedString("PAUSED")
                )
            }
        }

        await withTaskGroup(of: Void.self) { group in
            for task in tasks.values {
                group.addTask { await task.pause() }
            }
        }
    }

    @discardableResult
    func add(chapters: [AidokuRunner.Chapter], manga: AidokuRunner.Manga, autoStart: Bool = true) async -> [Download] {
        var downloads: [Download] = []
        for chapter in chapters {
            let identifier = ChapterIdentifier(
                sourceKey: manga.sourceKey,
                mangaKey: manga.key,
                chapterKey: chapter.key
            )
            guard !(await cache.isChapterDownloaded(identifier: identifier)),
                  queue[manga.sourceKey]?.contains(where: { $0.chapterIdentifier == identifier }) != true else {
                continue
            }

            // create tmp directory so we know it's queued
            let tmpDirectory = cache.tmpDirectory(for: identifier)
            tmpDirectory.removeItem() // remove in case it exists from a previous failed download
            tmpDirectory.createDirectory()

            let download = Download.from(manga: manga, chapter: chapter)
            downloads.append(download)
            if queue[manga.sourceKey] == nil {
                queue[manga.sourceKey] = [download]
                NotificationCenter.default.post(name: .downloadsQueued, object: [download])
            } else {
                queue[manga.sourceKey]?.append(download)
                // Publish before handing this entry to an already-running
                // worker, which can complete cached pages immediately.
                NotificationCenter.default.post(name: .downloadsQueued, object: [download])
                await tasks[manga.sourceKey]?.add(download: download)
            }
        }
        totalDownloads += downloads.count
        bgTask?.progress.totalUnitCount = Int64(totalDownloads)
        if autoStart {
            await start()
        }
        saveQueueState()
        return downloads
    }

    func cancelDownload(for chapter: ChapterIdentifier) async {
        if let task = tasks[chapter.sourceKey] {
            await task.cancel(chapter: chapter)
        } else {
            // no longer in queue but the tmp download directory still exists, so we should remove it
            cache.tmpDirectory(for: chapter).removeItem()
        }
        saveQueueState()
    }

    func cancelDownloads(for chapters: [ChapterIdentifier]) async {
        // disable individual download cancelled notifications
        sendCancelNotification = false
        defer { sendCancelNotification = true }
        for chapter in chapters {
            if let task = tasks[chapter.sourceKey] {
                await task.cancel(chapter: chapter)
            } else {
                cache.tmpDirectory(for: chapter).removeItem()
            }
            if let queueItem = queue[chapter.sourceKey]?.firstIndex(where: {
                $0.chapterIdentifier == chapter
            }) {
                queue[chapter.sourceKey]?.remove(at: queueItem)
            }
        }
        NotificationCenter.default.post(name: .downloadsCancelled, object: chapters)
        saveQueueState()
    }

    func cancelDownloads(for manga: MangaIdentifier) async {
        if let task = tasks[manga.sourceKey] {
            await task.cancel(manga: manga)
        } else {
            cache.directory(for: manga)
                .contentsIncludingHidden
                .filter {
                    $0.lastPathComponent.hasPrefix(DownloadCache.tmpDirectoryPrefix)
                        && !cache.hasFailureMarker(inTmpDirectory: $0)
                }
                .forEach { $0.removeItem() }
        }
        saveQueueState()
    }

    func cancelAll() async {
        // A late worker callback must not restart entries being canceled.
        paused = true
        sendCancelNotification = false
        defer { sendCancelNotification = true }
        for task in tasks {
            await task.value.cancel()
        }
        queue = [:]
        NotificationCenter.default.post(name: .downloadsCancelled, object: nil)
        saveQueueState()
    }

    // register callback for download progress change
    func onProgress(for chapter: ChapterIdentifier, block: @escaping (Int, Int) -> Void) {
        progressBlocks[chapter] = block
    }

    func removeProgressBlock(for chapter: ChapterIdentifier) {
        progressBlocks.removeValue(forKey: chapter)
    }

    func saveQueueState() {
        let queueData = try? JSONEncoder().encode(queue)
        UserDefaults.standard.set(queueData, forKey: "Data.downloadQueueState")
    }

    func loadQueueState() async {
        guard
            let queueData = UserDefaults.standard.data(forKey: "Data.downloadQueueState"),
            let queueState = try? JSONDecoder().decode([String: [Download]].self, from: queueData)
        else {
            return
        }
        queue = queueState
        if !queue.isEmpty {
            NotificationCenter.default.post(name: .downloadsQueued, object: queue.values.flatMap { $0 })
            await start()
        }
    }

    func hasQueuedDownloads() -> Bool {
        !queue.isEmpty
    }

    func isRunning() async -> Bool {
        for task in tasks where await task.value.running {
            return true
        }
        return false
    }
}

extension DownloadQueue {
    private func setBackgroundTask(_ task: ProgressReporting?) {
        bgTask = task
        if task == nil { backgroundTaskRequested = false }
        totalDownloads = queue.values.reduce(0) { $0 + $1.count }
        completedDownloads = 0
        bgTask?.progress.totalUnitCount = Int64(totalDownloads)
    }

    private func hasBackgroundTask() -> Bool { bgTask != nil }

#if !targetEnvironment(simulator)
    @available(iOS 26.0, *)
    private func register() async {
        guard !registeredTask else { return }
        registeredTask = true

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { @Sendable [weak self] task in
            guard let self, let task = task as? BGContinuedProcessingTask else { return }

            task.expirationHandler = {
                Task {
                    await DownloadManager.shared.pauseDownloads()
                    await self.setBackgroundTask(nil)
                }
                task.setTaskCompleted(success: false)
            }

            Task { @Sendable in
                await self.setBackgroundTask(task)
                await self.initAndResumeTasks()

                // Yield between checks. Expiration clears the task and ends
                // this waiter even when the user keeps a paused queue.
                while await self.hasBackgroundTask(), !(await self.queue.isEmpty) {
                    do { try await Task.sleep(for: .milliseconds(250)) }
                    catch { break }
                }
                guard await self.hasBackgroundTask() else { return }
                let completed = await self.queue.isEmpty
                await self.setBackgroundTask(nil)
                task.setTaskCompleted(success: completed)
            }
        }
    }
#endif
}

// MARK: - Task Delegate
extension DownloadQueue: DownloadTaskDelegate {
    func taskCancelled(task: DownloadTask) async {
        await taskFinished(task: task)
    }

    func taskPaused(task _: DownloadTask) async {}

    func taskFinished(task: DownloadTask) async {
        // The worker can drain just as add() gives this source more entries.
        // Ignore an older cycle if it resumed or has already been replaced.
        guard !(await task.running), tasks[task.id] === task else { return }
        tasks.removeValue(forKey: task.id)
        let pending = queue[task.id] ?? []
        if pending.isEmpty { queue.removeValue(forKey: task.id) }
        saveQueueState()
        if !paused, !pending.isEmpty { await initAndResumeTasks() }
    }

    func downloadFinished(download: Download) async {
        await downloadCancelled(download: download)
        progressBlocks.removeValue(forKey: download.chapterIdentifier)
        onCompletion?()
        NotificationCenter.default.post(name: .downloadFinished, object: download)
    }

    func downloadFailed(download: Download) async {
        await downloadCancelled(download: download)
        progressBlocks.removeValue(forKey: download.chapterIdentifier)
        onCompletion?()
        NotificationCenter.default.post(name: .downloadFailed, object: download)
    }

    func downloadCancelled(download: Download) async {
        var sourceDownloads = queue[download.chapterIdentifier.sourceKey] ?? []
        sourceDownloads.removeAll { $0 == download }
        if sourceDownloads.isEmpty {
            queue.removeValue(forKey: download.chapterIdentifier.sourceKey)
        } else {
            queue[download.chapterIdentifier.sourceKey] = sourceDownloads
        }
        saveQueueState()
        progressBlocks.removeValue(forKey: download.chapterIdentifier)
        if sendCancelNotification {
            NotificationCenter.default.post(name: .downloadCancelled, object: download)
        }

        completedDownloads += 1
        bgTask?.progress.completedUnitCount = Int64(completedDownloads)

        if #available(iOS 26.0, *) {
            if !paused, let task = bgTask as? BGContinuedProcessingTask {
                task.updateTitle(
                    NSLocalizedString("DOWNLOADING"),
                    subtitle: String(format: NSLocalizedString("%i_OF_%i"), completedDownloads, totalDownloads)
                )
            }
        }
    }

    func downloadProgressChanged(download: Download) async {
        guard let index = queue[download.chapterIdentifier.sourceKey]?.firstIndex(where: { $0 == download }) else { return }
        queue[download.chapterIdentifier.sourceKey]?[index] = download
        if let block = progressBlocks[download.chapterIdentifier] {
            block(download.progress, download.total)
        }
        NotificationCenter.default.post(name: .downloadProgressed, object: download)
    }
}
