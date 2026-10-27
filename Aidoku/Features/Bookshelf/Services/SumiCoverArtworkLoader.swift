#if SUMI
import AidokuRunner
import Combine
import Foundation
import Nuke
import UIKit

/// Catalog batches and visible tiles share the exact source-modified request
/// and processing key. Warm images can be installed synchronously when a new
/// section appears, rather than fading in one cover at a time.
@MainActor
final class SumiCoverArtworkLoader {
    typealias Loader = @MainActor @Sendable (SumiBook) async -> Void
    static let shared = SumiCoverArtworkLoader()

    private struct Key: Hashable {
        let id: MangaIdentifier
        let cover: URL?
        let source: ObjectIdentifier?
        let version: Int
        let preferences: Int

        init(book: SumiBook, source: AidokuRunner.Source?) {
            id = book.id
            cover = book.coverURL
            self.source = source.map(ObjectIdentifier.init)
            version = source?.version ?? 0
            preferences = SumiSearchSourcePreferences.fingerprint(sourceKey: book.sourceKey)
        }
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

    init(concurrency: Int = 4, timeout: Duration = .seconds(4), loader: Loader? = nil) {
        self.concurrency = max(1, concurrency)
        self.timeout = timeout
        self.loader = loader
        observer = NotificationCenter.default.publisher(for: .sourceUnloaded).sink { [weak self] notification in
            guard let sourceKey = notification.object as? String else { return }
            Task { @MainActor [weak self] in self?.remove(sourceKey: sourceKey) }
        }
    }

    func cachedCover(for book: SumiBook) -> UIImage? {
        let key = Key(book: book, source: currentSource(for: book.sourceKey))
        guard let request = requests[key]?.request else { return nil }
        return ImagePipeline.shared.cache.cachedImage(for: request, caches: [.memory])?.image
    }

    func usesPreparedPlaceholder(for book: SumiBook) -> Bool {
        let key = Key(book: book, source: currentSource(for: book.sourceKey))
        return placeholders[key].map { $0 > .now } ?? false
    }

    /// Wait briefly for the whole section's artwork. A broken image host cannot
    /// hold a source's metadata hostage; unavailable art keeps its placeholder
    /// for this presentation and can retry on a later refresh.
    func prepare(_ books: [SumiBook]) async {
        guard !Task.isCancelled, !books.isEmpty else { return }
        var seen: Set<MangaIdentifier> = []
        let missing = books.filter {
            seen.insert($0.id).inserted && $0.coverURL != nil && cachedCover(for: $0) == nil
                && !usesPreparedPlaceholder(for: $0)
        }
        guard !missing.isEmpty else { return }
        let completion = SumiCoverBatchCompletion()
        let work = Task { @MainActor [self] in
            await withTaskGroup(of: Void.self) { group in
                var next = 0
                for _ in 0..<min(concurrency, missing.count) {
                    let book = missing[next]
                    next += 1
                    group.addTask { @MainActor [self] in await warm(book) }
                }
                while await group.next() != nil {
                    guard !Task.isCancelled else { group.cancelAll(); return }
                    if next < missing.count {
                        let book = missing[next]
                        next += 1
                        group.addTask { @MainActor [self] in await warm(book) }
                    }
                }
            }
            completion.finish()
        }
        let deadline = Task { @MainActor [timeout] in
            do { try await Task.sleep(for: timeout); completion.finish() }
            catch { }
        }
        await withTaskCancellationHandler {
            await completion.wait()
        } onCancel: {
            work.cancel()
            deadline.cancel()
            Task { @MainActor in completion.finish() }
        }
        work.cancel()
        deadline.cancel()
        guard !Task.isCancelled else { return }
        let expiry = Date.now.addingTimeInterval(10)
        for book in missing where cachedCover(for: book) == nil {
            let key = Key(book: book, source: currentSource(for: book.sourceKey))
            placeholders[key] = expiry
        }
        trim()
    }

    func loadCover(for book: SumiBook, source providedSource: AidokuRunner.Source? = nil) async -> UIImage? {
        guard let url = book.coverURL, !Task.isCancelled else { return nil }
        let generation = sourceGenerations[book.sourceKey, default: 0]
        let source: AidokuRunner.Source?
        if let providedSource { source = providedSource }
        else if let loaded = SourceStore.shared.source(for: book.sourceKey) { source = loaded }
        else { source = await SourceManager.shared.source(for: book.sourceKey) }
        guard !Task.isCancelled, generation == sourceGenerations[book.sourceKey, default: 0] else { return nil }
        if let source { resolvedSources[book.sourceKey] = source }
        let key = Key(book: book, source: source)
        while active.contains(key) || active.count >= concurrency {
            do { try await Task.sleep(for: .milliseconds(20)) }
            catch { return nil }
            if let image = cachedCover(for: book) { return image }
            if usesPreparedPlaceholder(for: book) { return nil }
        }
        if let image = cachedCover(for: book) { return image }
        if usesPreparedPlaceholder(for: book) { return nil }
        guard !Task.isCancelled, generation == sourceGenerations[book.sourceKey, default: 0] else { return nil }
        active.insert(key)
        defer { active.remove(key) }
        let urlRequest: URLRequest
        if let local = url.toAidokuFileUrl() { urlRequest = URLRequest(url: local) }
        else if let source { urlRequest = await source.getModifiedImageRequest(url: url, context: nil) }
        else { urlRequest = URLRequest(url: url) }
        guard !Task.isCancelled, generation == sourceGenerations[book.sourceKey, default: 0] else { return nil }
        // 640 physical pixels are sufficient for library/search cover tiles;
        // avoid multiplying this decoded bitmap by a screen-scale factor.
        var processors: [ImageProcessing] = [DownsampleProcessor(width: 640, scaleFactor: 1)]
        if let source, source.features.processesCovers { processors.append(CoverInterceptorProcessor(source: source)) }
        let request = ImageRequest(urlRequest: urlRequest, processors: processors,
            userInfo: [.processesKey: source?.features.processesCovers ?? false])
        requests[key] = RequestEntry(request: request, source: source, stored: .now)
        trim()
        let image = try? await ImagePipeline.shared.image(for: request)
        guard !Task.isCancelled, generation == sourceGenerations[book.sourceKey, default: 0] else { return nil }
        if image == nil { placeholders[key] = Date.now.addingTimeInterval(10) }
        else { placeholders[key] = nil }
        return image
    }

    private func warm(_ book: SumiBook) async {
        if let loader { await loader(book) }
        else { _ = await loadCover(for: book) }
    }

    private func currentSource(for sourceKey: String) -> AidokuRunner.Source? {
        SourceStore.shared.source(for: sourceKey) ?? resolvedSources[sourceKey]
    }

    private func remove(sourceKey: String) {
        sourceGenerations[sourceKey, default: 0] += 1
        resolvedSources[sourceKey] = nil
        requests = requests.filter { $0.key.id.sourceKey != sourceKey }
        placeholders = placeholders.filter { $0.key.id.sourceKey != sourceKey }
    }

    private func trim() {
        placeholders = placeholders.filter { $0.value > .now }
        while requests.count > 256 {
            guard let oldest = requests.min(by: { $0.value.stored < $1.value.stored })?.key else { break }
            requests[oldest] = nil
        }
        let retainedKeys = Set(requests.keys.map(\.id.sourceKey))
        let activeKeys = Set(active.map(\.id.sourceKey))
        resolvedSources = resolvedSources.filter { retainedKeys.contains($0.key) || activeKeys.contains($0.key) }
    }
}
#endif
