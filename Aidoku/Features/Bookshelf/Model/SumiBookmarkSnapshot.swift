#if SUMI
/// An actual unfinished history position. A total is intentionally unnecessary:
/// sources can know the saved page before a chapter's page count is available.
struct SumiBookmarkSnapshot: Hashable, Sendable {
    let chapterKey: String
    let page: Int

    init?(chapterKey: String, page: Int, completed: Bool) {
        guard !completed, page > 0, !chapterKey.isEmpty else { return nil }
        self.chapterKey = chapterKey
        self.page = page
    }
}
#endif
