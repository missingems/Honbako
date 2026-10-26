@testable import Sumi
import AidokuRunner
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct SumiDiscoveryStoreTests {
    @Test("Metadata cache preserves canonical source IDs, order and original artwork URLs")
    func cacheRoundTrip() throws {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cache = SumiDiscoveryCache(url: url)
        var entries = manga(count: 3)
        entries[0].chapters = [.init(key: "never-cache-chapters")]
        try cache.save(entries)
        let restored = try cache.load()
        #expect(restored.map(\.identifier) == entries.map(\.identifier))
        #expect(restored.map(\.cover) == entries.map(\.cover))
        #expect(restored.allSatisfy { $0.sourceKey == "en.weebcentral" })
        #expect(restored.allSatisfy { $0.chapters == nil })
    }

    @Test("Discovery rejects duplicate IDs, duplicate cover URLs and unusable metadata")
    func uniqueRealMetadata() {
        let originals = manga(count: 2)
        let duplicateCover = AidokuRunner.Manga(sourceKey: "en.weebcentral", key: "another-id", title: "Another",
                                               cover: originals[0].cover)
        let withoutCover = AidokuRunner.Manga(sourceKey: "en.weebcentral", key: "no-cover", title: "Missing")
        let localPath = AidokuRunner.Manga(sourceKey: "en.weebcentral", key: "local", title: "Local", cover: "file:///tmp/cover.png")
        let foreign = AidokuRunner.Manga(sourceKey: "not-curated", key: "foreign", title: "Foreign", cover: "https://example.com/foreign.jpg")
        let selected = SumiDiscoveryStore.uniqueCandidates([originals[0], originals[0], duplicateCover,
                                                           withoutCover, localPath, foreign, originals[1]])
        #expect(selected.map(\.identifier) == originals.map(\.identifier))
    }

    @Test("A complete cached catalog never fetches or changes order on relaunch")
    func warmCache() async throws {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let entries = manga(count: 100)
        try SumiDiscoveryCache(url: url).save(entries)
        let store = SumiDiscoveryStore(cacheURL: url, catalogLoader: {
            Issue.record("A warm complete catalog must not access providers")
            return []
        })
        await store.populate()
        await store.populate()
        #expect(store.books.map(\.id) == entries.map(\.identifier))
        #expect(!store.isLoading)
        #expect(store.errorMessage == nil)
    }

    @Test("Concurrent population coalesces and the shuffled selection persists exactly")
    func coalescedPopulation() async throws {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let calls = LoaderCalls()
        let entries = manga(count: 128)
        let store = SumiDiscoveryStore(cacheURL: url, catalogLoader: {
            calls.count += 1
            try await Task.sleep(for: .milliseconds(30))
            return entries
        })
        async let first: Void = store.populate()
        async let second: Void = store.populate()
        _ = await (first, second)
        #expect(calls.count == 1)
        #expect(store.books.count == 100)
        #expect(Set(store.books.map(\.id)).count == 100)
        #expect(try SumiDiscoveryCache(url: url).load().map(\.identifier) == store.books.map(\.id))
    }

    @Test("Reset prevents a canceled late provider result from repopulating or saving")
    func resetDiscardsLateCompletion() async throws {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let gate = SuspendedCatalog()
        let store = SumiDiscoveryStore(cacheURL: url, catalogLoader: { await gate.load() })
        let pending = Task { await store.populate() }
        for _ in 0..<100 where !gate.started { try await Task.sleep(for: .milliseconds(5)) }
        #expect(gate.started)
        await store.reset()
        gate.finish(manga(count: 100))
        await pending.value
        #expect(store.books.isEmpty)
        #expect(!store.isLoading)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("A fresh install stays empty without creating a discovery cache")
    func firstLaunchHasNoPreloadedManga() async {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SumiDiscoveryStore(cacheURL: url)
        await store.populate()
        #expect(store.books.isEmpty)
        #expect(store.errorMessage == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("An older partial collection is preserved without filling it with new providers")
    func preservesPartialCollectionWithoutDiscovery() async throws {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let entries = manga(count: 3)
        try SumiDiscoveryCache(url: url).save(entries)
        let store = SumiDiscoveryStore(cacheURL: url)
        await store.populate()
        #expect(store.books.map(\.id) == entries.map(\.identifier))
        #expect(store.errorMessage == nil)
    }

    private func temporaryCacheURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "SumiDiscoveryTests-\(UUID())", directoryHint: .isDirectory)
            .appending(path: "catalog.json")
    }

    private func manga(count: Int) -> [AidokuRunner.Manga] {
        (0..<count).map {
            AidokuRunner.Manga(sourceKey: "en.weebcentral", key: "fixture-\($0)", title: "Fixture \($0)",
                               cover: "https://example.com/fixture-\($0).jpg")
        }
    }

    @MainActor private final class LoaderCalls { var count = 0 }

    @MainActor private final class SuspendedCatalog {
        var started = false
        private var continuation: CheckedContinuation<[AidokuRunner.Manga], Never>?

        func load() async -> [AidokuRunner.Manga] {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                started = true
            }
        }

        func finish(_ manga: [AidokuRunner.Manga]) {
            continuation?.resume(returning: manga)
            continuation = nil
        }
    }
}
