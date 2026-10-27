@testable import Sumi
import AidokuRunner
import Foundation
import Testing

struct SumiSearchPreparationServiceTests {
    @Test("Empty, locked, and unavailable chapters cannot become readable search results")
    func realChapterAvailability() {
        let open = AidokuRunner.Chapter(key: "open", language: "en")
        let locked = AidokuRunner.Chapter(key: "locked", language: "ja", locked: true)
        #expect(SumiSearchPreparationService.readableChapters(in: [], sourceAvailable: true) { _ in false }.isEmpty)
        #expect(SumiSearchPreparationService.readableChapters(in: [locked], sourceAvailable: true) { _ in false }.isEmpty)
        #expect(SumiSearchPreparationService.readableChapters(in: [open], sourceAvailable: false) { _ in false }.isEmpty)
        #expect(SumiSearchPreparationService.readableChapters(in: [locked, open], sourceAvailable: true) { _ in false }.map(\.key) == ["open"])
        #expect(SumiSearchPreparationService.readableChapters(in: [locked], sourceAvailable: false) { $0.key == "locked" }.map(\.key) == ["locked"])
    }

    @Test("Prepared rows contain their author, year, status, and title language together, in input order")
    func atomicPreparedRows() async throws {
        let slow = book("slow")
        let fast = book("fast")
        let gate = Gate()
        let publication = Publication()
        let service = SumiSearchPreparationService(concurrency: 2) { book, _ in
            if book.manga.key == "slow" { await gate.wait() }
            return Self.details(book)
        }
        let task = Task {
            let outcome = try await service.prepare([slow, fast])
            await publication.publish(outcome.books)
            return outcome
        }
        defer { task.cancel(); Task { await gate.release() } }
        try await Task.sleep(for: .milliseconds(30))
        #expect(await publication.books.isEmpty)
        await gate.release()
        let outcome = try await task.value
        #expect(outcome.books.map(\.manga.key) == ["slow", "fast"])
        for row in outcome.books {
            #expect(row.author == "Author")
            #expect(row.releaseYear == 2009)
            #expect(row.manga.status == .ongoing)
            #expect(row.searchLanguages?.codes == ["en"])
        }
    }

    @Test("Bounded preparation and cache reuse preserve current history instead of caching old Resume state")
    func boundedCachePreservesProgress() async throws {
        let probe = Probe()
        let service = SumiSearchPreparationService(concurrency: 2) { book, _ in
            await probe.begin()
            try await Task.sleep(for: .milliseconds(20))
            await probe.end()
            return Self.details(book)
        }
        let books = (0..<7).map { book("title-\($0)") }
        let outcome = try await service.prepare(books)
        #expect(outcome.books.count == 7)
        #expect(await probe.maximumActive <= 2)
        let resumed = SumiBook(manga: books[0].manga, chapterLabel: "Chapter 8", progress: 0.5,
                              lastRead: .now, lastReadPage: 19)
        let cached = try await service.prepare([resumed])
        #expect(await probe.count == 7)
        #expect(cached.books.first?.lastReadPage == 19)
        #expect(cached.books.first?.chapterLabel == "Chapter 8")
        #expect(cached.books.first?.author == "Author")
        let duplicate = book("shared-in-flight")
        async let first = service.prepare([duplicate])
        async let second = service.prepare([duplicate])
        let concurrent = try await [first, second]
        #expect(concurrent.allSatisfy { $0.books.count == 1 })
        #expect(await probe.count == 8)
        #expect(await probe.maximumActive <= 2)
    }

    @Test("Known empty results are cached and filtered while lookup failures stay retryable")
    func emptyVersusUnknown() async throws {
        let probe = Probe()
        let service = SumiSearchPreparationService { book, _ in
            await probe.begin()
            await probe.end()
            if book.manga.key == "unknown" { throw URLError(.timedOut) }
            return nil
        }
        let empty = book("empty")
        #expect(try await service.prepare([empty]).books.isEmpty)
        #expect(try await service.prepare([empty]).books.isEmpty)
        #expect(await probe.count == 1)
        let unknown = book("unknown")
        let failed = try await service.prepare([unknown])
        #expect(failed.books.isEmpty)
        #expect(failed.failedSourceKeys == [unknown.sourceKey])
        _ = try await service.prepare([unknown])
        #expect(await probe.count == 3)
    }

    @Test("Changing a source language invalidates cached availability instead of reusing another edition's evidence")
    func sourcePreferenceInvalidation() async throws {
        let sourceKey = "preparation-preferences-\(UUID().uuidString)"
        let preferenceKey = sourceKey + ".languages"
        defer { UserDefaults.standard.removeObject(forKey: preferenceKey) }
        let probe = Probe()
        let service = SumiSearchPreparationService { book, _ in
            await probe.begin()
            await probe.end()
            return Self.details(book)
        }
        let candidate = SumiBook(manga: .init(sourceKey: sourceKey, key: "title", title: "Title"))
        UserDefaults.standard.set(["en"], forKey: preferenceKey)
        _ = try await service.prepare([candidate])
        _ = try await service.prepare([candidate])
        #expect(await probe.count == 1)
        UserDefaults.standard.set(["ja"], forKey: preferenceKey)
        _ = try await service.prepare([candidate])
        #expect(await probe.count == 2)
    }

    @Test("Later completed batches append results and editions without moving an existing row or changing its source")
    func stablePublishedRows() {
        let first = SumiBook(manga: .init(sourceKey: "z-provider", key: "first", title: "One Piece", authors: ["Author"]))
        let edition = SumiBook(manga: .init(sourceKey: "a-provider", key: "edition", title: "One Piece", authors: ["Author"]))
        let exact = SumiBook(manga: .init(sourceKey: "a-provider", key: "exact", title: "One", authors: ["Other Author"]))
        let groups = SumiSearchRanking.stableGroups([first, edition, exact], query: "One", previouslyPublished: [first.id])
        #expect(groups.map(\.book.id) == [first.id, exact.id])
        #expect(Set(groups.first?.editions.map(\.id) ?? []) == [first.id, edition.id])
    }

    @Test("Cancelled searches cannot publish or cache a missing row for the next query")
    func cancellationDoesNotPoisonCache() async throws {
        let probe = Probe()
        let service = SumiSearchPreparationService { book, _ in
            await probe.begin()
            try await Task.sleep(for: .milliseconds(100))
            await probe.end()
            return Self.details(book)
        }
        let candidate = book("cancelled")
        let task = Task { try await service.prepare([candidate]) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await probe.count == 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(await probe.count == 1)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("A cancelled preparation unexpectedly published results")
        } catch is CancellationError { }
        let retry = try await service.prepare([candidate])
        #expect(retry.books.first?.author == "Author")
        #expect(await probe.count == 2)
    }

    private func book(_ key: String) -> SumiBook {
        SumiBook(manga: .init(sourceKey: "preparation-test", key: key, title: key))
    }

    private static func details(_ book: SumiBook) -> SumiSearchPreparationService.Details {
        var manga = book.manga
        manga.authors = ["Author"]
        manga.status = .ongoing
        return .init(manga: manga, releaseYear: 2009,
            languages: SumiSearchLanguageInfo(chapterLanguages: ["en"], sourceLanguages: ["ja", "en"]))
    }

    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false
        func wait() async {
            if released { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func release() { released = true; continuation?.resume(); continuation = nil }
    }

    private actor Publication {
        private(set) var books: [SumiBook] = []
        func publish(_ books: [SumiBook]) { self.books = books }
    }

    private actor Probe {
        private(set) var count = 0
        private var active = 0
        private(set) var maximumActive = 0
        func begin() { count += 1; active += 1; maximumActive = max(maximumActive, active) }
        func end() { active -= 1 }
    }
}
