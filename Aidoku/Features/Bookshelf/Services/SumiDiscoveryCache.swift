#if SUMI
import AidokuRunner
import Foundation

/// Small metadata only, independent of the user's library and chapter storage.
struct SumiDiscoveryCache {
    struct Entry: Codable {
        let sourceKey: String
        let manga: AidokuRunner.Manga

        init(_ manga: AidokuRunner.Manga) {
            sourceKey = manga.sourceKey
            var metadata = manga
            metadata.chapters = nil
            self.manga = metadata
        }

        var restored: AidokuRunner.Manga {
            // AidokuRunner deliberately excludes sourceKey from Manga.Codable.
            AidokuRunner.Manga(sourceKey: sourceKey, key: manga.key, title: manga.title).copy(from: manga)
        }
    }

    private struct Document: Codable {
        let version: Int
        let entries: [Entry]
    }

    let url: URL

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "SumiDiscovery", directoryHint: .isDirectory)
            .appending(path: "catalog-v1.json")
    }

    func load() throws -> [AidokuRunner.Manga] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 4_000_000 else { throw CacheError.invalidDocument }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        guard document.version == 1, document.entries.count <= 100 else { throw CacheError.invalidDocument }
        return document.entries.map(\.restored)
    }

    func save(_ manga: [AidokuRunner.Manga]) throws {
        let data = try JSONEncoder().encode(Document(version: 1, entries: manga.prefix(100).map(Entry.init)))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func remove() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private enum CacheError: Error { case invalidDocument }
}
#endif
