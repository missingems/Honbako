@testable import Sumi
import AidokuRunner
import Foundation
import Testing

@MainActor
struct HonbakoReaderChapterStateTests {
    @Test("Live queue events retain completed batch work and isolate other manga")
    func progressEvents() throws {
        let manga = AidokuRunner.Manga(sourceKey: "reader-state-test", key: UUID().uuidString, title: "Test")
        let state = HonbakoReaderChapterState(mangaID: manga.identifier, chapterKeys: ["one", "two"])
        var first = Download.from(manga: manga, chapter: .init(key: "one"), status: .downloading)
        first.progress = 5
        first.total = 10
        state.apply(first)
        #expect(state.progress == 0.5)
        state.apply(.from(manga: manga, chapter: .init(key: "two")))
        #expect(state.progress == 0.25)
        first.status = .finished
        first.progress = 10
        state.apply(first)
        #expect(state.progress == 0.5, "Completing one chapter does not reset the batch progress")
        #expect(state.activeDownloads.map(\.chapter.key) == ["two"])
        #expect(state.reading["one"]?.total == 10)
        var delayed = first
        delayed.status = .downloading
        delayed.progress = 9
        state.apply(delayed)
        #expect(state.statuses["one"] == .finished, "A late page callback cannot resurrect a completed download")
        let unrelated = AidokuRunner.Manga(sourceKey: manga.sourceKey, key: UUID().uuidString, title: "Other")
        state.apply(.from(manga: unrelated, chapter: .init(key: "one"), status: .failed))
        #expect(state.failedCount == 0)
        state.apply(.from(manga: manga, chapter: .init(key: "two"), status: .failed))
        #expect(state.failedCount == 1)
        #expect(state.completedCount == 1)
        #expect(state.activeDownloads.isEmpty)
        #expect(state.hasCopies)
    }

    @Test("Canceling an item removes its live progress without reporting a transfer failure")
    func cancellation() {
        let manga = AidokuRunner.Manga(sourceKey: "reader-state-test", key: UUID().uuidString, title: "Test")
        let state = HonbakoReaderChapterState(mangaID: manga.identifier, chapterKeys: ["one"])
        state.apply(.from(manga: manga, chapter: .init(key: "one")))
        state.apply(.from(manga: manga, chapter: .init(key: "one"), status: .cancelled))
        #expect(state.activeDownloads.isEmpty)
        #expect(state.failedCount == 0)
        #expect(state.statuses["one"] == .cancelled)
    }

    @Test("Reading labels clamp bookmarks, display completed totals, and avoid invented page counts")
    func readingLabels() {
        #expect(HonbakoChapterReadingProgress(page: 0, total: 20).label == "Pg 1 of 20")
        #expect(HonbakoChapterReadingProgress(page: 99, total: 20).label == "Pg 20 of 20")
        #expect(HonbakoChapterReadingProgress(page: 2, total: 20, completed: true).label == "Pg 20 of 20")
        #expect(HonbakoChapterReadingProgress(page: 4).label == "Pg 4")
        #expect(HonbakoChapterReadingProgress().label == "Unread")
    }
}
