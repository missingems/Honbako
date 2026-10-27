#if SUMI
import AidokuRunner
import Foundation

/// Popularity metadata stays separate from library/history and chapter storage.
/// File work runs on this actor rather than blocking the main UI actor.
actor HonbakoPopularCache {
    struct Catalog: Codable, Sendable {
        let identity: HonbakoPopularConnection.Identity
        let date: Date
        let entries: [AidokuRunner.Manga]

        var restored: [AidokuRunner.Manga] {
            let manga = entries.map { AidokuRunner.Manga(sourceKey: identity.sourceKey, key: $0.key, title: $0.title).copy(from: $0) }
            return HonbakoPopularAggregation.candidates(manga, sourceKey: identity.sourceKey)
        }
    }

    private struct Document: Codable {
        let version: Int
        let catalogs: [Catalog]
    }

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Honbako", directoryHint: .isDirectory)
            .appending(path: "popular-v1.json")
    }

    private let url: URL
    private var savedGeneration = 0

    init(url: URL) { self.url = url }

    func load() throws -> [Catalog] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 4_000_000 else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        guard document.version == 1, document.catalogs.count <= 64,
              Set(document.catalogs.map(\.identity)).count == document.catalogs.count,
              document.catalogs.allSatisfy({ catalog in
                  !catalog.identity.sourceKey.isEmpty && catalog.identity.sourceKey.count <= 512
                      && catalog.identity.revision.count <= 256
                      && catalog.entries.count <= HonbakoPopularAggregation.perSourceLimit
                      && catalog.restored.count == catalog.entries.count
              }) else { throw URLError(.cannotParseResponse) }
        return document.catalogs
    }

    func save(_ catalogs: [Catalog], generation: Int) throws {
        guard generation >= savedGeneration else { return }
        savedGeneration = generation
        let data = try JSONEncoder().encode(Document(version: 1, catalogs: Array(catalogs.prefix(64))))
        guard data.count <= 4_000_000 else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
#endif
