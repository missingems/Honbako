#if SUMI && DEBUG
import AidokuRunner
import Foundation

actor HonbakoCatalogPreviewRunner: AidokuRunner.Runner {
    nonisolated let features = AidokuRunner.SourceFeatures(providesListings: true)
    private let books: [AidokuRunner.Manga]
    private let pages: [String: [AidokuRunner.Page]]
    private let searchDelay: Duration

    init(books: [AidokuRunner.Manga], pages: [String: [AidokuRunner.Page]], searchDelay: Duration = .zero) {
        self.books = books
        self.pages = pages
        self.searchDelay = searchDelay
    }

    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
        if query?.isEmpty == false, searchDelay > .zero { try await Task.sleep(for: searchDelay) }
        try Task.checkCancellation()
        let query = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .init(entries: page == 1 ? books.filter { query.isEmpty || $0.title.localizedStandardContains(query) } : [],
                     hasNextPage: false)
    }

    func getMangaList(listing: AidokuRunner.Listing, page: Int) async throws -> AidokuRunner.MangaPageResult {
        .init(entries: page == 1 ? books : [], hasNextPage: false)
    }

    func getMangaUpdate(manga: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga {
        books.first { $0.identifier == manga.identifier } ?? manga
    }

    func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] {
        pages[chapter.key] ?? []
    }
}
#endif
