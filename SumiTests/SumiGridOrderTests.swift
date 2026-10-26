@testable import Sumi
import AidokuRunner
import Foundation
import Testing

@MainActor
struct SumiGridOrderTests {
    @Test("Opening books updates progress without moving their grid positions")
    func progressKeepsPositions() {
        var order = SumiGridOrder(defaults: nil)
        let catalog = [book("b"), book("a"), book("c")]
        let initial = order.books(catalog: catalog, library: [])
        let reading = book("c", page: 7, lastRead: .now)
        let updated = order.books(catalog: catalog, library: [reading, book("b")])
        #expect(updated.map(\.id) == initial.map(\.id))
        #expect(updated[2].pageLabel == "Page 7")
        #expect(updated[2].isInLibrary)
    }

    @Test("Relaunch keeps the collection order and appends newly saved titles")
    func persistentOrder() throws {
        let suite = "SumiGridOrderTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var first = SumiGridOrder(defaults: defaults)
        let catalog = [book("b"), book("a"), book("c")]
        let initial = first.books(catalog: catalog, library: [])
        var relaunched = SumiGridOrder(defaults: defaults)
        let updated = relaunched.books(catalog: Array(catalog.reversed()), library: [book("z"), book("a"), book("d")])
        #expect(Array(updated.prefix(3)).map(\.id) == initial.map(\.id))
        #expect(updated.map(\.manga.key) == ["b", "a", "c", "d", "z"])
    }

    @Test("Missing catalogs retain positions and duplicate entries do not create extra covers")
    func unavailableSourcesKeepTheirSlots() {
        var order = SumiGridOrder(defaults: nil)
        _ = order.books(catalog: [book("b"), book("a"), book("b")], library: [])
        #expect(order.books(catalog: [], library: [book("a")]).map(\.manga.key) == ["a"])
        let restored = order.books(catalog: [book("a"), book("b")], library: [book("a")])
        #expect(restored.map(\.manga.key) == ["b", "a"])
        #expect(order.identifiers.count == 2)
    }

    private func book(_ key: String, page: Int? = nil, lastRead: Date? = nil) -> SumiBook {
        SumiBook(manga: AidokuRunner.Manga(sourceKey: "en.weebcentral", key: key, title: key),
                 pageLabel: page.map { "Page \($0)" }, lastRead: lastRead)
    }
}
