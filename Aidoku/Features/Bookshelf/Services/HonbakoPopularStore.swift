#if SUMI
import AidokuRunner
import Combine
import Foundation

@MainActor
final class HonbakoPopularStore: ObservableObject {
    typealias ConnectionLoader = @MainActor @Sendable () async -> [HonbakoPopularConnection]
    typealias CoverPreparer = @Sendable ([SumiBook]) async -> Void

    @Published private(set) var books: [SumiBook] = []
    @Published private(set) var hasSources = false
    @Published private(set) var isLoading = false
    @Published private(set) var failures: Set<String> = []

    private let connectionLoader: ConnectionLoader
    private let coverPreparer: CoverPreparer
    private let cache: HonbakoPopularCache
    private let now: @MainActor () -> Date
    private var catalogs: [HonbakoPopularConnection.Identity: HonbakoPopularCache.Catalog] = [:]
    private var identities: [HonbakoPopularConnection.Identity] = []
    private var publishedOrder: [MangaIdentifier] = []
    private var hasLoadedCache = false
    private var isPaused = false
    private var loading: Task<Void, Never>?
    private var warming: Task<Void, Never>?
    private var requestGeneration = 0
    private var generation = 0
    private var observers: Set<AnyCancellable> = []
    private let lifetime: TimeInterval = 900

    init(cacheURL: URL = HonbakoPopularCache.defaultURL, observesSourceChanges: Bool = true,
         now: @escaping @MainActor () -> Date = { .now },
         coverPreparer: @escaping CoverPreparer = { await SumiCoverArtworkLoader.shared.prepare($0) },
         connectionLoader: ConnectionLoader? = nil) {
        cache = HonbakoPopularCache(url: cacheURL)
        self.now = now
        self.coverPreparer = coverPreparer
        self.connectionLoader = connectionLoader ?? {
            await SourceManager.shared.getLoadedSources().map(HonbakoPopularConnection.init(source:))
        }
        guard observesSourceChanges else { return }
        for name in [Notification.Name.updateSourceList, .sourceLoaded, UserDefaults.didChangeNotification] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refresh() }
            }.store(in: &observers)
        }
        NotificationCenter.default.publisher(for: .sourceUnloaded).sink { [weak self] notification in
            guard let key = notification.object as? String else { return }
            Task { @MainActor [weak self] in self?.remove(sourceKey: key) }
        }.store(in: &observers)
    }

    deinit { loading?.cancel(); warming?.cancel() }

    /// A typed search has priority over background catalog requests.
    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            requestGeneration += 1
            generation += 1
            loading?.cancel()
            loading = nil
            warming?.cancel()
            warming = nil
            isLoading = false
        }
    }

    func refresh() async {
        guard !isPaused else { return }
        requestGeneration += 1
        let request = requestGeneration
        let connections = await connectionLoader().sorted { $0.id.sourceKey < $1.id.sourceKey }
        guard request == requestGeneration, !Task.isCancelled, !isPaused else { return }
        if !hasLoadedCache {
            let restored = (try? await cache.load()) ?? []
            guard request == requestGeneration, !Task.isCancelled, !isPaused else { return }
            catalogs = Dictionary(uniqueKeysWithValues: restored.map { ($0.identity, $0) })
            hasLoadedCache = true
        }
        let connected = connections.map(\.id)
        if connected == identities, let loading {
            await loading.value
            return
        }
        if connected == identities, let warming {
            await warming.value
            return
        }
        let currentDate = now()
        let pending = connections.filter { connection in
            guard let catalog = catalogs[connection.id] else { return true }
            let age = currentDate.timeIntervalSince(catalog.date)
            return age < 0 || age >= lifetime
        }
        if connected == identities, pending.isEmpty,
           catalogs.keys.allSatisfy({ connected.contains($0) }) {
            // Fresh metadata can still have covers that timed out on a cold
            // connection. Retry their bounded batch when returning to the
            // library, then refresh the section together without a new catalog
            // request or a per-tile reveal.
            let current = generation
            await warmCovers(books, generation: current)
            guard generation == current, !Task.isCancelled, !isPaused,
                  connected == identities else { return }
            rebuildBooks()
            return
        }
        generation += 1
        let current = generation
        loading?.cancel()
        warming?.cancel()
        warming = nil
        identities = connected
        hasSources = !connected.isEmpty
        let allowed = Set(connected)
        catalogs = catalogs.filter { allowed.contains($0.key) }
        failures.formIntersection(Set(connected.map(\.sourceKey)))
        await warmCovers(identities.flatMap { catalogs[$0]?.restored ?? [] }.map { SumiBook(manga: $0) },
                         generation: current)
        guard generation == current, !Task.isCancelled, !isPaused else { return }
        rebuildBooks()
        guard !pending.isEmpty else {
            isLoading = false
            loading = nil
            await persist(generation: current)
            return
        }
        isLoading = true
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.load(pending, generation: current)
        }
        loading = task
        await task.value
        guard generation == current else { return }
        loading = nil
        isLoading = false
    }

    private func remove(sourceKey: String) {
        requestGeneration += 1
        generation += 1
        loading?.cancel()
        loading = nil
        warming?.cancel()
        warming = nil
        isLoading = false
        identities.removeAll { $0.sourceKey == sourceKey }
        catalogs = catalogs.filter { $0.key.sourceKey != sourceKey }
        hasSources = !identities.isEmpty
        failures.remove(sourceKey)
        rebuildBooks()
        let current = generation
        Task { await persist(generation: current) }
    }

    private func load(_ connections: [HonbakoPopularConnection], generation current: Int) async {
        let coverPreparer = self.coverPreparer
        await withTaskGroup(of: Result.self) { group in
            var next = 0
            for _ in 0..<min(3, connections.count) {
                let connection = connections[next]
                next += 1
                group.addTask { await Self.fetch(connection, coverPreparer: coverPreparer) }
            }
            while let result = await group.next() {
                guard !Task.isCancelled, generation == current else { group.cancelAll(); return }
                if identities.contains(result.identity) {
                    if let entries = result.entries {
                        catalogs[result.identity] = .init(identity: result.identity, date: now(), entries: entries)
                        failures.remove(result.identity.sourceKey)
                    } else if !result.cancelled { failures.insert(result.identity.sourceKey) }
                    rebuildBooks()
                    await persist(generation: current)
                }
                guard !Task.isCancelled, generation == current else { group.cancelAll(); return }
                if next < connections.count {
                    let connection = connections[next]
                    next += 1
                    group.addTask { await Self.fetch(connection, coverPreparer: coverPreparer) }
                }
            }
        }
    }

    private func warmCovers(_ books: [SumiBook], generation current: Int) async {
        guard !books.isEmpty, generation == current, !Task.isCancelled, !isPaused else { return }
        let coverPreparer = self.coverPreparer
        let task = Task { await coverPreparer(books) }
        warming = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard generation == current else { return }
        warming = nil
    }

    private struct Result: Sendable {
        let identity: HonbakoPopularConnection.Identity
        let entries: [AidokuRunner.Manga]?
        let cancelled: Bool
    }

    nonisolated private static func fetch(_ connection: HonbakoPopularConnection,
                                         coverPreparer: CoverPreparer) async -> Result {
        do {
            try Task.checkCancellation()
            let manga = try await connection.load()
            try Task.checkCancellation()
            let entries = HonbakoPopularAggregation.candidates(manga, sourceKey: connection.id.sourceKey)
            await coverPreparer(entries.map { SumiBook(manga: $0) })
            try Task.checkCancellation()
            return Result(identity: connection.id, entries: entries, cancelled: false)
        } catch is CancellationError { return Result(identity: connection.id, entries: nil, cancelled: true) }
        catch { return Result(identity: connection.id, entries: nil, cancelled: false) }
    }

    private func rebuildBooks() {
        let currentCatalogs = identities.compactMap { catalogs[$0]?.restored }
        let connectedKeys = Set(identities.map(\.sourceKey))
        let awaitingKeys = Set(identities.filter { catalogs[$0] == nil }.map(\.sourceKey))
        let availableIDs = Set(currentCatalogs.flatMap { $0.map(\.identifier) })
        // A new source revision must hide its old metadata immediately, but a
        // temporary empty grid must not discard the positions of those IDs.
        publishedOrder.removeAll {
            !connectedKeys.contains($0.sourceKey)
                || (!awaitingKeys.contains($0.sourceKey) && !availableIDs.contains($0))
        }
        let next = HonbakoPopularAggregation.books(catalogs: currentCatalogs, previouslyPublished: publishedOrder)
        let knownIDs = Set(publishedOrder)
        publishedOrder += next.map(\.id).filter { !knownIDs.contains($0) }
        books = next
    }

    private func persist(generation current: Int) async {
        guard generation == current else { return }
        let snapshot = identities.compactMap { catalogs[$0] }
        try? await cache.save(snapshot, generation: current)
    }
}
#endif
