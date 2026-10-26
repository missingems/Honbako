@testable import Sumi
import AidokuRunner
import Testing

@MainActor
struct SumiReaderChapterLoadTests {
    @Test("A late older chapter response cannot replace the chapter selected more recently")
    func newerSelectionWins() async {
        let manga = AidokuRunner.Manga(sourceKey: "sumi-race-test", key: "book", title: "Race")
        let model = ReaderPagedViewModel(source: nil, manga: manga)
        let requests = DeferredPages()
        model.sumiPageLoaderOverride = { await requests.pages(for: $0.key) }
        let older = AidokuRunner.Chapter(key: "older")
        let newer = AidokuRunner.Chapter(key: "newer")
        let first = Task { await model.loadPages(chapter: older) }
        while !requests.hasRequest("older") { await Task.yield() }
        let second = Task { await model.loadPages(chapter: newer) }
        while !requests.hasRequest("newer") { await Task.yield() }
        requests.resolve("newer", pages: [Sumi.Page(sourceId: manga.sourceKey, chapterId: "newer", index: 0)])
        let secondCommitted = await second.value
        #expect(secondCommitted)
        #expect(model.chapter?.key == "newer")
        #expect(model.pages.first?.chapterId == "newer")
        requests.resolve("older", pages: [Sumi.Page(sourceId: manga.sourceKey, chapterId: "older", index: 0)])
        let firstCommitted = await first.value
        #expect(!firstCommitted)
        #expect(model.chapter?.key == "newer")
        #expect(model.pages.first?.chapterId == "newer")
    }

    @MainActor private final class DeferredPages {
        private var requests: [String: CheckedContinuation<[Sumi.Page], Never>] = [:]
        func pages(for key: String) async -> [Sumi.Page] {
            await withCheckedContinuation { requests[key] = $0 }
        }
        func hasRequest(_ key: String) -> Bool { requests[key] != nil }
        func resolve(_ key: String, pages: [Sumi.Page]) { requests.removeValue(forKey: key)?.resume(returning: pages) }
    }
}
