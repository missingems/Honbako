#if SUMI
import AidokuRunner
import Foundation

enum HonbakoPopularAggregation {
    static let perSourceLimit = 20
    static let totalLimit = 120

    static func candidates(_ manga: [AidokuRunner.Manga], sourceKey: String) -> [AidokuRunner.Manga] {
        var seen: Set<MangaIdentifier> = []
        return manga.filter { item in
            guard item.sourceKey == sourceKey,
                  !item.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.contentRating != .nsfw,
                  let cover = item.cover, let url = URL(string: cover),
                  ["https", "http", "file", "aidoku-image"].contains(url.scheme?.lowercased() ?? ""),
                  seen.insert(item.identifier).inserted else { return false }
            return url.isFileURL || url.scheme == "aidoku-image" || url.host?.isEmpty == false
        }.prefix(perSourceLimit).map { item in
            var metadata = item
            metadata.chapters = nil
            return metadata
        }
    }

    /// Round-robin each source's own ranking. Titles already on screen retain
    /// their slots when another provider finishes or cached artwork refreshes.
    static func books(catalogs: [[AidokuRunner.Manga]], previouslyPublished: [MangaIdentifier]) -> [SumiBook] {
        let longest = catalogs.map(\.count).max() ?? 0
        let ranked = (0..<longest).flatMap { index in catalogs.compactMap { $0[safe: index] } }
        var seen: Set<MangaIdentifier> = []
        let unique = ranked.filter { seen.insert($0.identifier).inserted }
        let byID = Dictionary(uniqueKeysWithValues: unique.map { ($0.identifier, $0) })
        let previous = previouslyPublished.compactMap { byID[$0] }
        let previousIDs = Set(previous.map(\.identifier))
        let ordered = previous + unique.filter { !previousIDs.contains($0.identifier) }
        var selected: [AidokuRunner.Manga] = []
        for item in ordered {
            let title = SumiSearchRanking.normalized(item.title)
            let authors = Set((item.authors ?? []).map(SumiSearchRanking.normalized))
            let duplicate = selected.contains { other in
                guard title.count >= 3, SumiSearchRanking.normalized(other.title) == title else { return false }
                let known = Set((other.authors ?? []).map(SumiSearchRanking.normalized))
                return authors.isEmpty || known.isEmpty || !authors.isDisjoint(with: known)
            }
            if !duplicate { selected.append(item) }
            if selected.count == totalLimit { break }
        }
        return selected.map { SumiBook(manga: $0) }
    }
}
#endif
