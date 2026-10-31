#if SUMI
import AidokuRunner
import Combine
import Foundation
import Nuke
import UIKit

/// Catalog prewarming and NukeUI tiles share the same source-modified request.
/// A bounded decoded-cover cache survives reader-page cache churn; a warm tile
/// can show its print synchronously when it scrolls back into view.
@MainActor
final class SumiCoverArtworkLoader {
    typealias Loader = @MainActor @Sendable (SumiBook) async -> Void
    static let shared = SumiCoverArtworkLoader()

    static let batchPreparedNotification = Notification.Name("Honbako.CoverArtworkBatchPrepared")

    fileprivate struct Key: Hashable, Sendable {
        let id: MangaIdentifier
        let cover: URL?
        let source: ObjectIdentifier?
        let version: Int
        let preferences: Int
        let generation: Int
        let variant = "original-640-unlit-print-v3"

        init(book: SumiBook, source: AidokuRunner.Source?, preferences: Int, generation: Int) {
            id = book.id
            cover = book.coverURL
            self.source = source.map(ObjectIdentifier.init)
            version = source?.version ?? 0
            self.preferences = preferences
            self.generation = generation
        }
    }

    fileprivate struct LoadedCover: @unchecked Sendable {
        let key: Key
        let image: UIImage
        let generation: Int
    }

    struct PreparedBatch {
        fileprivate let entries: [MangaIdentifier: LoadedCover]
    }

    private struct Job: Sendable {
        let book: SumiBook
        let generation: Int
        let preferences: Int
        let ticket = UUID()
    }

    private struct WorkResult: @unchecked Sendable {
        let job: Job
        let cover: LoadedCover?
    }

    @MainActor
    private final class Cohort {
        var jobs: [MangaIdentifier: Job] = [:]
        var order: [MangaIdentifier] = []
        var queue: [MangaIdentifier] = []
        var running: [MangaIdentifier: UUID] = [:]
        var finished: Set<MangaIdentifier> = []
        var images: [MangaIdentifier: LoadedCover] = [:]
        var leases: [UUID: Set<MangaIdentifier>] = [:]
        var visible: Set<MangaIdentifier> = []
        var waiters: [UUID: SumiCoverBatchCompletion] = [:]
        var task: Task<Void, Never>?
        var watchdog: Task<Void, Never>?
    }

    private final class CacheKey: NSObject {
        let key: Key
        init(_ key: Key) { self.key = key }
        override var hash: Int { key.hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as? CacheKey)?.key == key }
    }

    private struct RequestEntry {
        let request: ImageRequest
        // Retain the instance while its ObjectIdentifier keys this request.
        let source: AidokuRunner.Source?
        let stored: Date
    }

    private let concurrency: Int
    private let timeout: Duration
    private let loader: Loader?
    private var requests: [Key: RequestEntry] = [:]
    private var placeholders: [Key: Date] = [:]
    private var active: Set<Key> = []
    private var resolvedSources: [String: AidokuRunner.Source] = [:]
    private var sourceGenerations: [String: Int] = [:]
    private var observer: AnyCancellable?
    private var memoryObserver: AnyCancellable?
    private var preferencesObserver: AnyCancellable?
    private var preferenceFingerprints: [String: Int] = [:]
    // Reader pages share Nuke's main cache and can evict an entire grid while a
    // book is open. Keep a bounded decoded grid edition independently so return
    // and back-scrolling can use the same bitmap without another decode.
    private let decodedCovers = NSCache<CacheKey, UIImage>()
    private var cohort: Cohort?
    private var imageTasks: [Key: ImageTask] = [:]
    private var cancelledImageTasks: Set<Key> = []
    private let cohortLimit = 64

    init(concurrency: Int = 4, timeout: Duration = .seconds(4), loader: Loader? = nil) {
        self.concurrency = max(1, concurrency)
        self.timeout = timeout
        self.loader = loader
        decodedCovers.totalCostLimit = min(192 * 1024 * 1024, Int(ProcessInfo.processInfo.physicalMemory / 32))
        decodedCovers.countLimit = 256
        memoryObserver = NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.releaseDecodedCoversForMemoryPressure() }
            }
        preferencesObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.invalidateChangedPreferences() }
            }
        observer = NotificationCenter.default.publisher(for: .sourceUnloaded).sink { [weak self] notification in
            guard let sourceKey = notification.object as? String else { return }
            Task { @MainActor [weak self] in self?.remove(sourceKey: sourceKey) }
        }
    }

    /// Memory pressure may release decoded copies; library refreshes never do.
    func releaseDecodedCoversForMemoryPressure() {
        decodedCovers.removeAllObjects()
    }

    func cachedCover(for book: SumiBook) -> UIImage? {
        rawCachedCover(for: book)?.image
    }

    private func rawCachedCover(for book: SumiBook) -> LoadedCover? {
        let key = key(for: book)
        let image: UIImage
        if let retained = decodedCovers.object(forKey: CacheKey(key)) { image = retained }
        else {
            guard let request = requests[key]?.request,
                  let cached = ImagePipeline.shared.cache.cachedImage(for: request, caches: [.memory])?.image else { return nil }
            image = cached
            retainDecodedCover(image, for: key)
        }
        return LoadedCover(key: key, image: image, generation: sourceGenerations[book.sourceKey, default: 0])
    }

    func usesPreparedPlaceholder(for book: SumiBook) -> Bool {
        cohort?.jobs[book.id] != nil || usesFailurePlaceholder(for: book)
    }

    private func usesFailurePlaceholder(for book: SumiBook) -> Bool {
        let key = key(for: book)
        return placeholders[key].map { $0 > .now } ?? false
    }

    /// The UI waits at most four seconds. Its bounded, coalesced cohort keeps
    /// warming afterward and publishes finished artwork in one main-actor pass.
    func prepare(_ books: [SumiBook]) async {
        guard !Task.isCancelled, !books.isEmpty else { return }
        var seen: Set<MangaIdentifier> = []
        let missing = books.filter {
            seen.insert($0.id).inserted && $0.coverURL != nil && cachedCover(for: $0) == nil
                && !usesFailurePlaceholder(for: $0)
        }
        guard !missing.isEmpty else { return }
        let lease = UUID()
        let batch = enqueue(Array(missing.prefix(cohortLimit)), lease: lease)
        let completion = SumiCoverBatchCompletion()
        batch.waiters[lease] = completion
        let deadline = Task { @MainActor [timeout] in
            do { try await Task.sleep(for: timeout); completion.finish() }
            catch { }
        }
        await withTaskCancellationHandler {
            await completion.wait()
        } onCancel: {
            deadline.cancel()
            Task { @MainActor [weak self] in
                self?.cancel(lease: lease, in: batch)
                completion.finish()
            }
        }
        deadline.cancel()
        batch.waiters[lease] = nil
        if Task.isCancelled { cancel(lease: lease, in: batch) }
    }

    func loadCover(for book: SumiBook, source providedSource: AidokuRunner.Source? = nil) async -> UIImage? {
        await loadCoverEntry(for: book, source: providedSource)?.image
    }

    /// The outer display gets a separate 2048px decoded edition. Keep the
    /// library's smaller edition visible while this original-resolution print loads.
    func loadDisplayCover(for book: SumiBook, source: AidokuRunner.Source?) async -> UIImage? {
        guard let coverURL = book.coverURL, !Task.isCancelled else { return nil }
        let url = Self.highQualityCoverURL(coverURL)
        let request: URLRequest
        if let local = url.toAidokuFileUrl() { request = URLRequest(url: local) }
        else if let source { request = await source.getModifiedImageRequest(url: url, context: nil) }
        else { request = URLRequest(url: url) }
        guard !Task.isCancelled else { return nil }
        var processors: [ImageProcessing] = []
        if let source, source.features.processesCovers { processors.append(CoverInterceptorProcessor(source: source)) }
        processors.append(DownsampleProcessor(width: 2048, scaleFactor: 1))
        let task = ImagePipeline.shared.imageTask(with: ImageRequest(urlRequest: request, processors: processors,
            userInfo: [.processesKey: source?.features.processesCovers ?? false]))
        let image = await withTaskCancellationHandler {
            try? await task.image
        } onCancel: { task.cancel() }
        return Task.isCancelled ? nil : image
    }

    /// NukeUI and explicit prewarming use one stable source-modified request.
    /// Reusing this request also avoids asking a source to regenerate headers
    /// every time SwiftUI recreates a previously visited tile.
    func coverRequest(for book: SumiBook, source providedSource: AidokuRunner.Source? = nil) async -> ImageRequest? {
        guard let coverURL = book.coverURL, !Task.isCancelled else { return nil }
        let url = Self.highQualityCoverURL(coverURL)
        let generation = sourceGenerations[book.sourceKey, default: 0]
        let source: AidokuRunner.Source?
        if let providedSource { source = providedSource }
        else if let current = currentSource(for: book.sourceKey) { source = current }
        else { source = await SourceManager.shared.source(for: book.sourceKey) }
        guard !Task.isCancelled, generation == sourceGenerations[book.sourceKey, default: 0],
              source != nil || url.isFileURL || url.toAidokuFileUrl() != nil
                || Self.permitsUnconfiguredSourceCover(url) else { return nil }
        if let source { resolvedSources[book.sourceKey] = source }
        let key = key(for: book, source: source)
        for previous in requests.keys where previous.id == key.id && previous != key {
            decodedCovers.removeObject(forKey: CacheKey(previous))
            requests[previous] = nil
        }
        if let existing = requests[key] { return existing.request }
        let urlRequest: URLRequest
        if let local = url.toAidokuFileUrl() { urlRequest = URLRequest(url: local) }
        else if let source { urlRequest = await source.getModifiedImageRequest(url: url, context: nil) }
        else { urlRequest = URLRequest(url: url) }
        guard !Task.isCancelled, generation == sourceGenerations[book.sourceKey, default: 0] else { return nil }
        var processors: [ImageProcessing] = []
        if let source, source.features.processesCovers { processors.append(CoverInterceptorProcessor(source: source)) }
        // Enough physical pixels for the library's compact tiles without the
        // decoded-memory churn of a 1024px edition for every book.
        processors.append(DownsampleProcessor(width: 640, scaleFactor: 1))
        var request = ImageRequest(urlRequest: urlRequest, processors: processors,
            userInfo: [.processesKey: source?.features.processesCovers ?? false])
        // Scope processed images to this source instance/preferences/generation.
        // The opaque hash contains no raw headers or credentials. Encoded bytes
        // retain the existing shared disk-cache policy.
        request.imageID = "Honbako.library-cover.\(key.hashValue)"
        requests[key] = RequestEntry(request: request, source: source, stored: .now)
        trim()
        return request
    }

    func retainVisibleCover(_ image: UIImage, for book: SumiBook, request: ImageRequest) {
        let key = key(for: book)
        guard let current = requests[key]?.request,
              ImagePipeline.shared.cache.makeImageCacheKey(for: current) == ImagePipeline.shared.cache.makeImageCacheKey(for: request) else { return }
        retainDecodedCover(image, for: key)
        placeholders[key] = nil
    }

    private func retainDecodedCover(_ image: UIImage, for key: Key) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height }
            ?? Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        decodedCovers.setObject(image, forKey: CacheKey(key), cost: cost)
    }

    func recordVisibleFailure(for book: SumiBook) {
        placeholders[key(for: book)] = Date.now.addingTimeInterval(10)
    }

    func isInFailureCooldown(for book: SumiBook) -> Bool { usesFailurePlaceholder(for: book) }

    private func loadCoverEntry(for book: SumiBook, source providedSource: AidokuRunner.Source? = nil) async -> LoadedCover? {
        guard let request = await coverRequest(for: book, source: providedSource) else { return nil }
        let generation = sourceGenerations[book.sourceKey, default: 0]
        let key = key(for: book)
        while active.contains(key) || active.count >= concurrency {
            do { try await Task.sleep(for: .milliseconds(20)) }
            catch { return nil }
            if let cached = rawCachedCover(for: book) { return cached }
            if usesFailurePlaceholder(for: book) { return nil }
        }
        if let cached = rawCachedCover(for: book) { return cached }
        if usesFailurePlaceholder(for: book) { return nil }
        guard !Task.isCancelled, generation == sourceGenerations[book.sourceKey, default: 0] else { return nil }
        active.insert(key)
        defer { active.remove(key) }
        let imageTask = ImagePipeline.shared.imageTask(with: request)
        imageTasks[key] = imageTask
        cancelledImageTasks.remove(key)
        defer { imageTasks[key] = nil; cancelledImageTasks.remove(key) }
        let image = try? await imageTask.image
        guard !Task.isCancelled, !cancelledImageTasks.contains(key),
              generation == sourceGenerations[book.sourceKey, default: 0] else { return nil }
        if let image { retainDecodedCover(image, for: key); placeholders[key] = nil }
        else { placeholders[key] = Date.now.addingTimeInterval(10) }
        return image.map { LoadedCover(key: key, image: $0, generation: generation) }
    }

    /// Compatibility prewarm for callers that explicitly request a cohort.
    /// Visible NukeUI tiles do not wait for other covers in that cohort.
    func requestVisibleCover(for book: SumiBook) {
        guard book.coverURL != nil, !usesPreparedPlaceholder(for: book) else { return }
        _ = enqueue([book], lease: nil)
    }

    func preparedCover(for book: SumiBook, in batch: PreparedBatch) -> UIImage? {
        guard let entry = batch.entries[book.id], isCurrent(entry, for: book) else { return nil }
        return entry.image
    }

    private func isCurrent(_ entry: LoadedCover, for book: SumiBook) -> Bool {
        entry.generation == sourceGenerations[book.sourceKey, default: 0]
            && entry.key == key(for: book)
    }

    private func enqueue(_ books: [SumiBook], lease: UUID?) -> Cohort {
        let batch: Cohort
        if let current = cohort, current.task?.isCancelled != true { batch = current }
        else { batch = Cohort(); cohort = batch }
        var incoming: [MangaIdentifier] = []
        var seen: Set<MangaIdentifier> = []
        for book in books.prefix(cohortLimit) where seen.insert(book.id).inserted {
            incoming.append(book.id)
            let generation = sourceGenerations[book.sourceKey, default: 0]
            let preferences = preferenceFingerprint(for: book.sourceKey)
            if let old = batch.jobs[book.id], old.book.coverURL == book.coverURL,
               old.generation == generation, old.preferences == preferences { continue }
            if batch.jobs[book.id] != nil { cancelImageTasks(for: [book.id]) }
            batch.jobs[book.id] = Job(book: book, generation: generation, preferences: preferences)
            batch.finished.remove(book.id)
            batch.images[book.id] = nil
        }
        // New visible work takes priority, retaining each input list's order.
        // There is one cohort, with at most 64 queued/running/staged identities.
        seen.removeAll(keepingCapacity: true)
        let priority = (incoming + batch.order).filter { seen.insert($0).inserted }
        let order = Array(priority.prefix(cohortLimit))
        let retained = Set(order)
        let dropped = Set(batch.jobs.keys).subtracting(retained)
        cancelImageTasks(for: dropped)
        batch.jobs = batch.jobs.filter { retained.contains($0.key) }
        batch.images = batch.images.filter { retained.contains($0.key) }
        batch.finished.formIntersection(retained)
        batch.visible.formIntersection(retained)
        batch.order = order
        batch.queue = order.filter { !batch.finished.contains($0) }
        for key in Array(batch.leases.keys) {
            batch.leases[key]?.formIntersection(retained)
            if batch.leases[key]?.isEmpty == true { batch.leases[key] = nil }
        }
        if let lease { batch.leases[lease] = Set(incoming).intersection(retained) }
        else { batch.visible.formUnion(incoming.filter { retained.contains($0) }) }
        if batch.task == nil {
            batch.task = Task { @MainActor [weak self, batch] in
                guard let self else { return }
                await run(batch)
            }
            batch.watchdog = Task { @MainActor [weak self, weak batch] in
                do { try await Task.sleep(for: .seconds(45)) } catch { return }
                guard let self, let batch, cohort === batch else { return }
                for (id, ticket) in batch.running {
                    guard let job = batch.jobs[id], job.ticket == ticket,
                          job.generation == sourceGenerations[job.book.sourceKey, default: 0] else { continue }
                    let key = key(for: job.book)
                    placeholders[key] = Date.now.addingTimeInterval(10)
                }
                batch.task?.cancel()
                cancelImageTasks(for: Set(batch.jobs.keys))
            }
        }
        return batch
    }

    private func run(_ batch: Cohort) async {
        await withTaskGroup(of: WorkResult.self) { group in
            var running = 0
            while cohort === batch, !Task.isCancelled {
                while running < concurrency, let job = takeJob(from: batch) {
                    running += 1
                    group.addTask { @MainActor [self] in
                        WorkResult(job: job, cover: await warm(job.book))
                    }
                }
                guard running > 0, let result = await group.next() else { break }
                running -= 1
                let id = result.job.book.id
                if batch.running[id] == result.job.ticket { batch.running[id] = nil }
                guard batch.jobs[id]?.ticket == result.job.ticket,
                      result.job.generation == sourceGenerations[result.job.book.sourceKey, default: 0] else { continue }
                batch.finished.insert(id)
                if let cover = result.cover, isCurrent(cover, for: result.job.book) { batch.images[id] = cover }
            }
            if Task.isCancelled || cohort !== batch { group.cancelAll() }
        }
        finish(batch)
    }

    private func takeJob(from batch: Cohort) -> Job? {
        guard let index = batch.queue.firstIndex(where: { batch.running[$0] == nil }) else { return nil }
        let id = batch.queue.remove(at: index)
        guard let job = batch.jobs[id], !batch.finished.contains(id) else { return takeJob(from: batch) }
        batch.running[id] = job.ticket
        return job
    }

    private func cancel(lease: UUID, in batch: Cohort) {
        guard cohort === batch, let withdrawn = batch.leases.removeValue(forKey: lease) else { return }
        let retained = batch.leases.values.reduce(into: batch.visible) { $0.formUnion($1) }
        let removed = withdrawn.subtracting(retained)
        cancelImageTasks(for: removed)
        for id in removed { batch.jobs[id] = nil; batch.images[id] = nil; batch.finished.remove(id) }
        batch.queue.removeAll { removed.contains($0) }
        batch.order.removeAll { removed.contains($0) }
        if batch.jobs.isEmpty { batch.task?.cancel() }
    }

    private func finish(_ batch: Cohort) {
        batch.watchdog?.cancel()
        batch.watchdog = nil
        guard cohort === batch else {
            batch.waiters.values.forEach { $0.finish() }
            batch.task = nil
            return
        }
        let entries = batch.images.filter { id, cover in
            batch.jobs[id].map { isCurrent(cover, for: $0.book) } ?? false
        }
        cohort = nil
        batch.task = nil
        batch.waiters.values.forEach { $0.finish() }
        batch.waiters.removeAll()
        trim()
        // The payload retains all ready bitmaps through this synchronous pass,
        // even if the shared Nuke cache evicted an early result in the meantime.
        NotificationCenter.default.post(name: Self.batchPreparedNotification, object: PreparedBatch(entries: entries))
    }

    private func cancelImageTasks(for ids: Set<MangaIdentifier>) {
        for (key, task) in imageTasks where ids.contains(key.id) {
            cancelledImageTasks.insert(key)
            task.cancel()
        }
    }

    /// Library records can arrive from iCloud before their source is restored.
    /// Public HTTPS artwork needs no extension or server login; personal-server
    /// addresses still wait for their configured source and modified request.
    static func permitsUnconfiguredSourceCover(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https", components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let value = components.host?.lowercased() else { return false }
        let credentialFields: Set<String> = ["token", "access_token", "auth_token", "api_key", "apikey", "auth", "authorization", "password", "secret", "session", "sessionid", "jwt"]
        guard !(components.queryItems ?? []).contains(where: {
            credentialFields.contains($0.name.lowercased().replacingOccurrences(of: "-", with: "_"))
        }) else { return false }
        let host = value.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard host.contains("."), !host.contains(":"),
              !host.allSatisfy({ $0.isNumber || $0 == "." }),
              !["localhost", "local", "lan", "internal", "home", "home.arpa"].contains(where: {
                  host == $0 || host.hasSuffix(".\($0)")
              }) else { return false }
        return true
    }

    /// Older saved MangaDex entries retain a thumbnail URL. Upgrade only its
    /// documented uploads path; every other provider keeps its exact URL and
    /// still receives its own source-modified headers below.
    private static func highQualityCoverURL(_ url: URL) -> URL {
        let parts = url.pathComponents
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "uploads.mangadex.org",
              parts.count == 4, parts[1] == "covers", UUID(uuidString: parts[2]) != nil,
              let suffix = [".256.jpg", ".512.jpg"].first(where: { parts[3].hasSuffix($0) }),
              parts[3].count > suffix.count,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.percentEncodedPath.hasSuffix(suffix) else { return url }
        components.percentEncodedPath = String(components.percentEncodedPath.dropLast(suffix.count))
        return components.url ?? url
    }

    private func warm(_ book: SumiBook) async -> LoadedCover? {
        if let loader {
            await loader(book)
            return rawCachedCover(for: book)
        }
        return await loadCoverEntry(for: book)
    }

    /// A cheap identity check for reused tiles; preferences are re-read once per
    /// source when defaults change, never copied/serialized for every tile update.
    func coverIdentity(for book: SumiBook) -> AnyHashable { AnyHashable(key(for: book)) }

    private func key(for book: SumiBook, source: AidokuRunner.Source? = nil) -> Key {
        Key(book: book, source: source ?? currentSource(for: book.sourceKey),
            preferences: preferenceFingerprint(for: book.sourceKey), generation: sourceGenerations[book.sourceKey, default: 0])
    }

    private func preferenceFingerprint(for sourceKey: String) -> Int {
        if let existing = preferenceFingerprints[sourceKey] { return existing }
        let value = SumiSearchSourcePreferences.fingerprint(sourceKey: sourceKey)
        preferenceFingerprints[sourceKey] = value
        return value
    }

    private func invalidateChangedPreferences() {
        for (sourceKey, previous) in preferenceFingerprints {
            let current = SumiSearchSourcePreferences.fingerprint(sourceKey: sourceKey)
            guard current != previous else { continue }
            remove(sourceKey: sourceKey)
            preferenceFingerprints[sourceKey] = current
        }
    }

    private func currentSource(for sourceKey: String) -> AidokuRunner.Source? {
        SourceStore.shared.source(for: sourceKey) ?? resolvedSources[sourceKey]
    }

    private func remove(sourceKey: String) {
        sourceGenerations[sourceKey, default: 0] += 1
        cancelImageTasks(for: Set(imageTasks.keys.filter { $0.id.sourceKey == sourceKey }.map(\.id)))
        if let batch = cohort {
            let removed = Set(batch.jobs.keys.filter { $0.sourceKey == sourceKey })
            cancelImageTasks(for: removed)
            for id in removed { batch.jobs[id] = nil; batch.images[id] = nil; batch.finished.remove(id) }
            batch.queue.removeAll { removed.contains($0) }
            batch.order.removeAll { removed.contains($0) }
            batch.visible.subtract(removed)
            if batch.jobs.isEmpty { batch.task?.cancel() }
        }
        resolvedSources[sourceKey] = nil
        for key in requests.keys where key.id.sourceKey == sourceKey { decodedCovers.removeObject(forKey: CacheKey(key)) }
        requests = requests.filter { $0.key.id.sourceKey != sourceKey }
        placeholders = placeholders.filter { $0.key.id.sourceKey != sourceKey }
    }

    private func trim() {
        placeholders = placeholders.filter { $0.value > .now }
        while requests.count > 256 {
            guard let oldest = requests.min(by: { $0.value.stored < $1.value.stored })?.key else { break }
            requests[oldest] = nil
            decodedCovers.removeObject(forKey: CacheKey(oldest))
        }
        let retainedKeys = Set(requests.keys.map(\.id.sourceKey))
        let activeKeys = Set(active.map(\.id.sourceKey))
        resolvedSources = resolvedSources.filter { retainedKeys.contains($0.key) || activeKeys.contains($0.key) }
    }
}
#endif
