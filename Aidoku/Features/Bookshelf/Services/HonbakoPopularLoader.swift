#if SUMI
import AidokuRunner
import Foundation

/// Only sections explicitly described by the provider as popular/ranked count.
/// An alphabetical collection or recent-updates listing is not popularity data.
enum HonbakoPopularLoader {
    static func load(source: AidokuRunner.Source) async throws -> [AidokuRunner.Manga] {
        try Task.checkCancellation()
        let listings = (try? await source.getListings()) ?? []
        try Task.checkCancellation()
        if let listing = popularListing(in: listings) {
            do {
                let result = try await source.getMangaList(listing: listing, page: 1)
                try Task.checkCancellation()
                return result.entries
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Personal servers can represent a listing with home components.
                if let home = try await source.getListingHome(listing: listing) {
                    try Task.checkCancellation()
                    return home.components.flatMap(manga(in:))
                }
                if source.features.providesHome {
                    return popularManga(in: try await source.getHome())
                }
                throw error
            }
        }
        guard source.features.providesHome else { return [] }
        let home = try await source.getHome()
        try Task.checkCancellation()
        return popularManga(in: home)
    }

    static func popularListing(in listings: [AidokuRunner.Listing]) -> AidokuRunner.Listing? {
        listings.first { isPopularLabel($0.id) || isPopularLabel($0.name) }
    }

    static func popularManga(in home: AidokuRunner.Home) -> [AidokuRunner.Manga] {
        home.components.filter { component in
            if case let .mangaList(ranking, _, _, _) = component.value, ranking { return true }
            return [component.title, component.subtitle].compactMap { $0 }.contains(where: isPopularLabel)
        }.flatMap(manga(in:))
    }

    static func isPopularLabel(_ label: String) -> Bool {
        let label = label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US_POSIX"))
        let words = label.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined()
        let tokens = Set(words.split(whereSeparator: \.isWhitespace).map(String.init))
        if !tokens.isDisjoint(with: ["popular", "popularity", "trending", "rank", "ranking", "rankings", "bestsellers", "hot", "top"]) {
            return true
        }
        if label.contains("most viewed") || label.contains("most read") || label.contains("most followed")
            || label.contains("best sellers") || label.contains("most favorites") { return true }
        return ["熱門", "热门", "人氣", "人气", "排行", "人気", "ランキング", "인기"].contains { label.contains($0) }
    }

    private static func manga(in component: AidokuRunner.HomeComponent) -> [AidokuRunner.Manga] {
        switch component.value {
        case let .bigScroller(entries, _): entries
        case let .imageScroller(entries, _, _, _), let .scroller(entries, _),
             let .mangaList(_, _, entries, _), let .links(entries):
            entries.compactMap { link in
                guard case var .manga(manga) = link.value else { return nil }
                if manga.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { manga.title = link.title }
                if manga.cover?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { manga.cover = link.imageUrl }
                return manga
            }
        case let .mangaChapterList(_, entries, _): entries.map(\.manga)
        case .filters: []
        }
    }
}
#endif
