@testable import Sumi
import AidokuRunner
import Foundation
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct HonbakoDownloadQueueTests {
    @Test("Requeueing an active chapter preserves its files and does not duplicate its queue entry")
    func duplicateDownloadPreservesActiveTransfer() async throws {
        let defaults = UserDefaults.standard
        let previousQueue = defaults.object(forKey: "Data.downloadQueueState")
        let manga = AidokuRunner.Manga(sourceKey: "download-test-\(UUID().uuidString)", key: "book", title: "Test")
        let chapter = AidokuRunner.Chapter(key: "chapter")
        let id = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key)
        let cache = DownloadCache()
        let queue = DownloadQueue(cache: cache)
        defer {
            cache.directory(sourceKey: manga.sourceKey).removeItem()
            defaults.set(previousQueue, forKey: "Data.downloadQueueState")
        }
        let initial = await queue.add(chapters: [chapter], manga: manga, autoStart: false)
        #expect(initial.count == 1)
        let activePage = cache.tmpDirectory(for: id).appendingPathComponent("001.png")
        try Data("transfer-in-progress".utf8).write(to: activePage)
        let duplicate = await queue.add(chapters: [chapter], manga: manga, autoStart: false)
        #expect(duplicate.isEmpty)
        #expect(try Data(contentsOf: activePage) == Data("transfer-in-progress".utf8))
        let queued = await queue.queue[manga.sourceKey] ?? []
        #expect(queued.count == 1)
        await queue.cancelAll()
    }
    private actor Events: DownloadTaskDelegate {
        private(set) var failures: [Download] = []
        private(set) var finished: [Download] = []
        private(set) var ordered: [Download] = []
        func taskCancelled(task: DownloadTask) async {}
        func taskPaused(task: DownloadTask) async {}
        func taskFinished(task: DownloadTask) async {}
        func downloadProgressChanged(download: Download) async { ordered.append(download) }
        func downloadFinished(download: Download) async { finished.append(download); ordered.append(download) }
        func downloadFailed(download: Download) async { failures.append(download) }
        func downloadCancelled(download: Download) async {}
    }

    @Test("A removed source produces a retryable failed download instead of silently dropping its chapter")
    func missingSourceIsVisibleFailure() async throws {
        let manga = AidokuRunner.Manga(sourceKey: "removed-download-test-\(UUID().uuidString)", key: "book", title: "Test")
        let chapter = AidokuRunner.Chapter(key: "chapter")
        let download = Download.from(manga: manga, chapter: chapter)
        let cache = DownloadCache()
        defer { cache.directory(sourceKey: manga.sourceKey).removeItem() }
        let events = Events()
        let worker = DownloadTask(id: manga.sourceKey, cache: cache, downloads: [download])
        defer { Task { await worker.cancel() } }
        await worker.setDelegate(delegate: events)
        await worker.resume()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await events.failures.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let failure = try #require(await events.failures.first)
        #expect(failure.status == .failed)
        #expect(await events.finished.isEmpty)
        #expect(cache.hasFailureMarker(inTmpDirectory: cache.tmpDirectory(for: download.chapterIdentifier)))
    }

    private actor ImageRunner: AidokuRunner.Runner {
        nonisolated let features = AidokuRunner.SourceFeatures()
        let pages: [AidokuRunner.Page]
        init(pages: [AidokuRunner.Page]) { self.pages = pages }
        func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
            .init(entries: [], hasNextPage: false)
        }
        func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga { manga }
        func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] { pages }
    }

    @Test("A successful two-page transfer stores distinct readable pages and finishes after ordered real progress")
    func successfulImageTransfer() async throws {
        let defaults = UserDefaults.standard
        let compressionKey = AppSettings.downloads.compress.key
        let previousCompression = defaults.object(forKey: compressionKey)
        defaults.set(false, forKey: compressionKey)
        let manga = AidokuRunner.Manga(sourceKey: "image-download-test-\(UUID().uuidString)", key: "book", title: "Test")
        let chapter = AidokuRunner.Chapter(key: "chapter")
        let download = Download.from(manga: manga, chapter: chapter)
        let cache = DownloadCache()
        defer {
            cache.directory(sourceKey: manga.sourceKey).removeItem()
            defaults.set(previousCompression, forKey: compressionKey)
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 6), format: format)
        let red = renderer.image { output in UIColor.red.setFill(); output.fill(CGRect(x: 0, y: 0, width: 4, height: 6)) }
        let blue = renderer.image { output in UIColor.blue.setFill(); output.fill(CGRect(x: 0, y: 0, width: 4, height: 6)) }
        let runner = ImageRunner(pages: [.init(content: .image(red)), .init(content: .image(blue))])
        let source = AidokuRunner.Source(key: manga.sourceKey, name: "Local Transfer Test", version: 1,
            languages: ["en"], contentRating: .safe, runner: runner)
        let events = Events()
        let worker = DownloadTask(id: manga.sourceKey, cache: cache, downloads: [download], sourceLookup: { key in
            key == source.key ? source : nil
        })
        defer { Task { await worker.cancel() } }
        await worker.setDelegate(delegate: events)
        await worker.resume()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await events.finished.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let finished = try #require(await events.finished.first)
        #expect(finished.status == .finished)
        #expect(finished.progress == 2 && finished.total == 2)
        #expect(await events.failures.isEmpty)
        let ordered = await events.ordered
        #expect(ordered.last?.status == .finished)
        #expect(ordered.dropLast().allSatisfy { $0.status == .downloading })
        #expect(ordered.dropLast().filter { $0.total == 2 }.map(\.progress) == [0, 1, 2])
        let first = try Data(contentsOf: cache.directory(for: download.chapterIdentifier).appendingPathComponent("001.png"))
        let second = try Data(contentsOf: cache.directory(for: download.chapterIdentifier).appendingPathComponent("002.png"))
        #expect(first != second)
        #expect(first == red.pngData() && second == blue.pngData(), "Stored order matches the source order")
        #expect(UIImage(data: first) != nil && UIImage(data: second) != nil)
        #expect(DownloadManager.shared.getDownloadStatus(for: download.chapterIdentifier) == .finished)
        let offline = await DownloadManager.shared.getDownloadedPages(for: download.chapterIdentifier)
        #expect(offline.count == 2, "The normal offline reader can enumerate the completed chapter")
    }

    private final class NotificationEvents: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []
        func append(_ value: String) { lock.withLock { events.append(value) } }
        var snapshot: [String] { lock.withLock { events } }
    }

    @Test("Queued is published once before a fast worker can publish progress or completion")
    func queuedNotificationPrecedesWorker() async throws {
        let defaults = UserDefaults.standard
        let previousQueue = defaults.object(forKey: "Data.downloadQueueState")
        let previousCompression = defaults.object(forKey: AppSettings.downloads.compress.key)
        defaults.set(false, forKey: AppSettings.downloads.compress.key)
        let manga = AidokuRunner.Manga(sourceKey: "notification-order-test-\(UUID().uuidString)", key: "book", title: "Test")
        let chapter = AidokuRunner.Chapter(key: "chapter")
        let cache = DownloadCache()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { output in
            UIColor.black.setFill(); output.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let source = AidokuRunner.Source(key: manga.sourceKey, name: "Notification Ordering", version: 1,
            languages: ["en"], contentRating: .safe, runner: ImageRunner(pages: [.init(content: .image(image))]))
        let events = NotificationEvents()
        let center = NotificationCenter.default
        var observers: [NSObjectProtocol] = []
        for (name, label) in [(Notification.Name.downloadsQueued, "queued"), (.downloadProgressed, "progress"), (.downloadFinished, "finished")] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { notification in
                let payload = (notification.object as? [Download]) ?? (notification.object as? Download).map { [$0] } ?? []
                if payload.contains(where: { $0.mangaIdentifier == manga.identifier }) { events.append(label) }
            })
        }
        defer {
            observers.forEach { center.removeObserver($0) }
            cache.directory(sourceKey: manga.sourceKey).removeItem()
            defaults.set(previousQueue, forKey: "Data.downloadQueueState")
            defaults.set(previousCompression, forKey: AppSettings.downloads.compress.key)
        }
        let queue = DownloadQueue(cache: cache, sourceLookup: { key in key == source.key ? source : nil })
        await queue.add(chapters: [chapter], manga: manga, autoStart: true)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !events.snapshot.contains("finished"), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let recorded = events.snapshot
        #expect(recorded.first == "queued")
        #expect(recorded.filter { $0 == "queued" }.count == 1)
        #expect(recorded.contains("progress"))
        #expect(recorded.last == "finished")
    }

    private actor FirstLookupGate {
        let source: AidokuRunner.Source
        private var continuation: CheckedContinuation<Void, Never>?
        private var calls = 0
        private var released = false
        private(set) var started = false
        init(source: AidokuRunner.Source) { self.source = source }
        func lookup(_ key: String) async -> AidokuRunner.Source? {
            guard key == source.key else { return nil }
            calls += 1
            if calls == 1, !released {
                started = true
                await withCheckedContinuation { continuation = $0 }
            }
            return source
        }
        func release() { released = true; continuation?.resume(); continuation = nil }
    }

    @Test("A draining worker preserves new source entries, restarts them, and ignores its stale completion")
    func drainingWorkerCannotDropPendingEntries() async throws {
        let defaults = UserDefaults.standard
        let previousQueue = defaults.object(forKey: "Data.downloadQueueState")
        let previousCompression = defaults.object(forKey: AppSettings.downloads.compress.key)
        defaults.set(false, forKey: AppSettings.downloads.compress.key)
        let manga = AidokuRunner.Manga(sourceKey: "draining-worker-test-\(UUID().uuidString)", key: "book", title: "Test")
        let first = AidokuRunner.Chapter(key: "one")
        let second = AidokuRunner.Chapter(key: "two")
        let cache = DownloadCache()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { output in
            UIColor.black.setFill(); output.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let source = AidokuRunner.Source(key: manga.sourceKey, name: "Worker Lifetime", version: 1,
            languages: ["en"], contentRating: .safe, runner: ImageRunner(pages: [.init(content: .image(image))]))
        let gate = FirstLookupGate(source: source)
        let queue = DownloadQueue(cache: cache, sourceLookup: { await gate.lookup($0) })
        defer {
            Task { await gate.release(); await queue.cancelAll() }
            cache.directory(sourceKey: manga.sourceKey).removeItem()
            defaults.set(previousQueue, forKey: "Data.downloadQueueState")
            defaults.set(previousCompression, forKey: AppSettings.downloads.compress.key)
        }
        await queue.add(chapters: [first], manga: manga, autoStart: true)
        let startedDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await gate.started), ContinuousClock.now < startedDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(await gate.started)
        let drained = try #require(await queue.tasks[manga.sourceKey])
        // Reproduce the delegate boundary deterministically: this worker has
        // stopped, but its source already owns a new pending queue entry.
        await drained.pause()
        await queue.add(chapters: [second], manga: manga, autoStart: false)
        await queue.taskFinished(task: drained)
        await queue.taskFinished(task: drained)
        let identifiers = [first, second].map {
            ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: $0.key)
        }
        let completedDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while identifiers.contains(where: { DownloadManager.shared.getDownloadStatus(for: $0) != .finished }),
              ContinuousClock.now < completedDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(identifiers.allSatisfy { DownloadManager.shared.getDownloadStatus(for: $0) == .finished })
        let settledDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await queue.hasQueuedDownloads(), ContinuousClock.now < settledDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await queue.hasQueuedDownloads() == false)
        await gate.release()
        await queue.cancelAll()
    }

}
