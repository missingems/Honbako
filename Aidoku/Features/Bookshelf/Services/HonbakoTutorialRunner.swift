#if SUMI
import AidokuRunner
import Foundation

actor HonbakoTutorialRunner: AidokuRunner.Runner {
    nonisolated let features = AidokuRunner.SourceFeatures()

    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
        guard page == 1 else { return .init(entries: [], hasNextPage: false) }
        var books = [try await HonbakoTutorialManga.makeManga()]
        for guide in HonbakoGuideBook.allCases { books.append(try await HonbakoGuideLibrary.makeManga(guide)) }
        let query = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .init(entries: books.filter { query.isEmpty || $0.title.localizedStandardContains(query)
            || ($0.description?.localizedStandardContains(query) ?? false) }, hasNextPage: false)
    }

    func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga {
        if let guide = HonbakoGuideBook(rawValue: manga.key) { return try await HonbakoGuideLibrary.makeManga(guide) }
        guard manga.key == HonbakoTutorialManga.mangaKey else { throw URLError(.resourceUnavailable) }
        return try await HonbakoTutorialManga.makeManga()
    }

    func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] {
        if let guide = HonbakoGuideBook(rawValue: manga.key) { return try await HonbakoGuideLibrary.pages(guide: guide, chapter: chapter) }
        guard manga.key == HonbakoTutorialManga.mangaKey else { throw URLError(.resourceUnavailable) }
        return try await HonbakoTutorialManga.pages(for: chapter)
    }
}
#endif
