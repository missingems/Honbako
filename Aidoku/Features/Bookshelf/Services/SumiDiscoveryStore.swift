#if SUMI
import AidokuRunner
import Combine
import Foundation

/// Discovery never adds titles to Reading or requests chapter pages. The first
/// successful shuffled selection is cached, so reopening keeps the same grid.
@MainActor
final class SumiDiscoveryStore: ObservableObject {
    typealias CatalogLoader = @MainActor @Sendable () async throws -> [AidokuRunner.Manga]

    @Published private(set) var books: [SumiBook] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    static let targetCount = 100
    private let cache: SumiDiscoveryCache
    private let catalogLoader: CatalogLoader?
    private var population: Task<Void, Never>?
    private var generation = 0
    private var hasLoadedCache = false

    init(cacheURL: URL = SumiDiscoveryCache.defaultURL, catalogLoader: CatalogLoader? = nil) {
        cache = SumiDiscoveryCache(url: cacheURL)
        self.catalogLoader = catalogLoader
    }

    deinit { population?.cancel() }

    func populate() async {
        if let population {
            await population.value
            return
        }
        guard books.count < Self.targetCount else { return }
        generation += 1
        let current = generation
        isLoading = true
        errorMessage = nil
        let task = Task { [weak self] in
            guard let self else { return }
            await self.load(generation: current)
        }
        population = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard generation == current else { return }
        population = nil
        isLoading = false
    }

    func cancel() {
        generation += 1
        population?.cancel()
        population = nil
        isLoading = false
    }

    /// Explicit refresh only; ordinary launches never reshuffle a complete grid.
    func reset() async {
        cancel()
        books = []
        hasLoadedCache = false
        do { try cache.remove(); errorMessage = nil }
        catch { errorMessage = "The discovery catalog could not be reset. Try again." }
    }

    private func load(generation current: Int) async {
        if !hasLoadedCache {
            hasLoadedCache = true
            do { books = Self.uniqueCandidates(try cache.load()).prefix(Self.targetCount).map { SumiBook(manga: $0) } }
            catch { /* A damaged metadata cache can be rebuilt from the catalogs. */ }
        }
        guard !Task.isCancelled, generation == current else { return }
        if books.count >= Self.targetCount { return }
        // Existing installations retain their cached collection. A new install
        // starts empty; source catalogs are searched only by an explicit query.
        guard let catalogLoader else { return }
        do {
            let loaded = try await catalogLoader()
            guard !Task.isCancelled, generation == current else { return }
            let existing = books.map(\.manga)
            let existingIDs = Set(existing.map(\.identifier))
            let existingCovers = Set(existing.compactMap(\.cover))
            let additions = Self.uniqueCandidates(loaded).filter {
                !existingIDs.contains($0.identifier) && !existingCovers.contains($0.cover ?? "")
            }.shuffled()
            let selected = Array((existing + additions).prefix(Self.targetCount))
            books = selected.map { SumiBook(manga: $0) }
            if selected.count < Self.targetCount {
                errorMessage = "Loaded \(selected.count) of \(Self.targetCount) books. Some catalogs are unavailable. Try again."
            }
            do { try cache.save(selected) }
            catch { errorMessage = "The books are ready, but their order could not be saved for next time." }
        } catch {
            guard !Task.isCancelled, generation == current else { return }
            errorMessage = books.isEmpty
                ? "The catalogs could not be loaded. Check your connection and try again."
                : "Showing \(books.count) saved books. The remaining catalogs could not be loaded. Try again."
        }
    }

    static func uniqueCandidates(_ manga: [AidokuRunner.Manga]) -> [AidokuRunner.Manga] {
        let allowed = Set(SumiCatalogBootstrap.curatedSourceKeys)
        var seen: Set<MangaIdentifier> = []
        var covers: Set<String> = []
        return manga.filter { book in
            guard allowed.contains(book.sourceKey), !book.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !book.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  book.contentRating != .nsfw,
                  let cover = book.cover, let url = URL(string: cover),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
                  !seen.contains(book.identifier), !covers.contains(cover) else { return false }
            seen.insert(book.identifier)
            covers.insert(cover)
            return true
        }
    }

}
#endif
