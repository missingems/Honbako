#if SUMI
import AidokuRunner
import Foundation

/// Freeze the accepted selection before the database is touched. A retry after
/// termination must finish the same fifty books, even if source rankings move.
struct HonbakoPersonalEnglishManifest: Codable, Sendable {
    let version: Int
    let validatedAt: Date
    let prepared: HonbakoPersonalEnglishCatalog.Prepared
}

struct HonbakoPersonalEnglishManifestStore: Sendable {
    enum ManifestError: Error { case invalidSelection }
    let url: URL

    func loadOrPrepare(
        _ prepare: () async throws -> HonbakoPersonalEnglishCatalog.Prepared
    ) async throws -> HonbakoPersonalEnglishManifest {
        if FileManager.default.fileExists(atPath: url.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(HonbakoPersonalEnglishManifest.self, from: Data(contentsOf: url))
            try validate(manifest)
            return manifest
        }
        let manifest = HonbakoPersonalEnglishManifest(version: 1, validatedAt: .now, prepared: try await prepare())
        // An incomplete source response has never touched the library, so it
        // may safely be fetched again. Only an accepted fifty is made durable.
        guard manifest.prepared.entries.count == 50 else { return manifest }
        try validate(manifest)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(manifest).write(to: url, options: .atomic)
        return manifest
    }

    private func validate(_ manifest: HonbakoPersonalEnglishManifest) throws {
        let entries = manifest.prepared.entries
        guard manifest.version == 1, entries.count == 50,
              Set(entries.map { $0.manga.identifier }).count == 50,
              entries.allSatisfy({ entry in
                  entry.manga.sourceKey == HonbakoMangaDexRunner.sourceKey
                      && UUID(uuidString: entry.manga.key) != nil
                      && entry.verifiedPageCount > 0
                      && !entry.chapters.isEmpty
                      && entry.chapters.allSatisfy { $0.language?.lowercased() == "en" && !$0.locked }
                      && entry.chapters.contains { $0.key == entry.verifiedChapterID }
              }) else { throw ManifestError.invalidSelection }
    }
}

extension HonbakoPersonalEnglishCatalog.Entry: Codable {
    private enum CodingKeys: String, CodingKey {
        case rank, sourceKey, manga, chapters, verifiedChapterID, verifiedPageCount
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        rank = try values.decode(Int.self, forKey: .rank)
        let sourceKey = try values.decode(String.self, forKey: .sourceKey)
        let decodedManga = try values.decode(AidokuRunner.Manga.self, forKey: .manga)
        // Manga intentionally excludes sourceKey from Codable. Restore the
        // manifest's explicit identity before any duplicate or history lookup.
        manga = AidokuRunner.Manga(sourceKey: sourceKey, key: decodedManga.key, title: decodedManga.title)
            .copy(from: decodedManga)
        chapters = try values.decode([AidokuRunner.Chapter].self, forKey: .chapters)
        verifiedChapterID = try values.decode(String.self, forKey: .verifiedChapterID)
        verifiedPageCount = try values.decode(Int.self, forKey: .verifiedPageCount)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(rank, forKey: .rank)
        try values.encode(manga.sourceKey, forKey: .sourceKey)
        try values.encode(manga, forKey: .manga)
        try values.encode(chapters, forKey: .chapters)
        try values.encode(verifiedChapterID, forKey: .verifiedChapterID)
        try values.encode(verifiedPageCount, forKey: .verifiedPageCount)
    }
}
#endif
