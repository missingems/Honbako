#if SUMI
import AidokuRunner
import Foundation

actor HonbakoTutorialRunner: AidokuRunner.Runner {
    nonisolated let features = AidokuRunner.SourceFeatures()

    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
        let manga = try await HonbakoTutorialManga.makeManga()
        let matches = query.map { $0.isEmpty || manga.title.localizedStandardContains($0) } ?? true
        return .init(entries: page == 1 && matches ? [manga] : [], hasNextPage: false)
    }

    func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga {
        guard manga.key == HonbakoTutorialManga.mangaKey else { throw URLError(.resourceUnavailable) }
        return try await HonbakoTutorialManga.makeManga()
    }

    func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] {
        guard manga.key == HonbakoTutorialManga.mangaKey else { throw URLError(.resourceUnavailable) }
        return try await HonbakoTutorialManga.pages(for: chapter)
    }
}
#endif
