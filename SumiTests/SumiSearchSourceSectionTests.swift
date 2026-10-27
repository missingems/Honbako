@testable import Sumi
import AidokuRunner
import Testing

struct SumiSearchSourceSectionTests {
    @Test("Source sections retain each edition and its provenance, including matching titles")
    func sourceProvenance() {
        let first = SumiBook(manga: .init(sourceKey: "first", key: "shared", title: "Shared Manga"))
        let second = SumiBook(manga: .init(sourceKey: "second", key: "shared", title: "Shared Manga"))
        let other = SumiBook(manga: .init(sourceKey: "first", key: "other", title: "Another Manga"))
        let sections = SumiSearchSourceSection.grouping([first, second, other]) { "Catalog \($0)" }
        #expect(sections.map(\.id) == ["first", "second"])
        #expect(sections.map(\.name) == ["Catalog first", "Catalog second"])
        #expect(sections[0].books.map(\.id) == [first.id, other.id])
        #expect(sections[1].books.map(\.id) == [second.id])
        #expect(sections[1].books[0].title == sections[0].books[0].title)
    }

    @Test("A newly ready source appends without displacing the first visible source")
    func stableSourceOrder() {
        let fast = SumiBook(manga: .init(sourceKey: "z-fast", key: "one", title: "Ready Manga"))
        let slow = SumiBook(manga: .init(sourceKey: "a-slow", key: "two", title: "Late Manga"))
        let before = SumiSearchSourceSection.grouping([fast]) { $0 }
        let after = SumiSearchSourceSection.grouping([fast, slow]) { $0 }
        #expect(before.first?.id == after.first?.id)
        #expect(after.map(\.id) == ["z-fast", "a-slow"])
        #expect(SumiSearchSourceSection.grouping([]) { $0 }.isEmpty)
    }
}
