@testable import Sumi
import AidokuRunner
import Testing

struct SumiSearchRankingTests {
    @Test("Matching titles collapse across sources and keep selectable editions")
    func exactDuplicates() {
        let first = book("One-Punch Man", source: "first", authors: ["ONE"])
        let second = book("one punch man", source: "second", authors: ["One"])
        let groups = SumiSearchRanking.groups([second, first, first], query: "one punch")
        #expect(groups.count == 1)
        #expect(groups[0].editions.count == 2)
        #expect(Set(groups[0].editions.map(\.sourceKey)) == ["first", "second"])
    }

    @Test("A saved edition wins without source completion order affecting ranking")
    func deterministicBestEdition() {
        let saved = book("Manga", source: "z", saved: true)
        let other = book("Manga", source: "a")
        let publisher = book("Manga", source: "multi.mangaplus")
        let forward = SumiSearchRanking.groups([saved, other, publisher], query: "manga")
        let backward = SumiSearchRanking.groups([publisher, other, saved], query: "manga")
        #expect(forward.map(\.book.id) == backward.map(\.book.id))
        #expect(forward[0].book.id == saved.id)
        #expect(forward[0].editions.map(\.id) == backward[0].editions.map(\.id))
    }

    @Test("Different authors, sequel numbers and editions within one source stay distinct")
    func conservativeMatching() {
        let works = [
            book("A Story", source: "one", authors: ["Author One"]),
            book("A Story", source: "two", authors: ["Author Two"]),
            book("A Story 2", source: "three", authors: ["Author One"]),
            book("A Story", source: "one", key: "deluxe", authors: ["Author One"])
        ]
        #expect(SumiSearchRanking.groups(works, query: "a story").count == 4)
    }

    @Test("Exact query match outranks an unrelated saved title")
    func queryFirst() {
        let exact = book("Blue", source: "a")
        let partial = book("Blue Period", source: "b", saved: true)
        #expect(SumiSearchRanking.groups([partial, exact], query: "Blue").first?.book.id == exact.id)
    }

    @Test("Known locked-only editions do not displace a readable search result")
    func readableEditionFirst() {
        let locked = SumiBook(manga: .init(sourceKey: "multi.mangaplus", key: "locked", title: "Manga",
            chapters: [.init(key: "locked-chapter", locked: true)]))
        let readable = SumiBook(manga: .init(sourceKey: "provider", key: "readable", title: "Manga",
            chapters: [.init(key: "readable-chapter")]))
        #expect(SumiSearchRanking.groups([locked, readable], query: "manga").first?.book.id == readable.id)
    }

    private func book(_ title: String, source: String, key: String = "title", authors: [String]? = nil,
                      saved: Bool = false) -> SumiBook {
        SumiBook(manga: .init(sourceKey: source, key: key, title: title, authors: authors), isInLibrary: saved)
    }
}
