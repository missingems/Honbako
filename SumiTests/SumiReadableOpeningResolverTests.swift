@testable import Sumi
import AidokuRunner
import Foundation
import Testing

@MainActor
struct SumiReadableOpeningResolverTests {
    @Test("An empty first chapter opens the next readable chapter with one sequential probe per choice")
    func emptyFirstChapter() async throws {
        let chapters = (1...4).reversed().map { Chapter(key: "\($0)", language: "en") }
        let choices = SumiReaderOpeningPolicy.candidates(history: nil, chaptersNewestFirst: chapters, canRead: { !$0.locked })
        var calls: [String] = []
        let result = try await SumiReadableOpeningResolver.resolve(choices, state: { _ in .unknown }) { choice in
            calls.append(choice.chapterKey)
            return choice.chapterKey == "3"
        }
        #expect(calls == ["1", "2", "3"])
        #expect(result == .init(chapterKey: "3", startPage: 1, isFirstRead: true))
    }

    @Test("A missing resume chapter advances within its language without copying another chapter's bookmark")
    func resumeReplacementKeepsLanguageAndOwnPage() async throws {
        let chapters = [Chapter(key: "en-3", language: "en"), Chapter(key: "ja-3", language: "ja"),
                        Chapter(key: "en-2", language: "en"), Chapter(key: "en-1", language: "en")]
        let history = SumiReaderHistorySnapshot(chapterKey: "en-2", page: 19, completed: false)
        let choices = SumiReaderOpeningPolicy.candidates(history: history,
            chaptersNewestFirst: SumiChapterLanguage.filter(chapters, language: "en"), canRead: { _ in true })
        var calls: [String] = []
        let result = try await SumiReadableOpeningResolver.resolve(choices, state: { _ in .unknown }) { choice in
            calls.append(choice.chapterKey)
            if choice.chapterKey == "en-2" { throw HonbakoMangaDexError.requestFailed(404) }
            return true
        }
        #expect(calls == ["en-2", "en-3"])
        #expect(result == .init(chapterKey: "en-3", startPage: 1, isFirstRead: false))
        #expect(history.page == 19 && history.chapterKey == "en-2", "Probing must not rewrite the saved history")
    }

    @Test("Known unavailable entries cost no probes and a later known readable chapter survives the request budget")
    func requestBudgetStillAllowsKnownReadable() async throws {
        let choices = (1...30).map { SumiReaderOpeningPolicy.Choice(chapterKey: "\($0)", startPage: 1, isFirstRead: true) }
        var calls: [String] = []
        let result = try await SumiReadableOpeningResolver.resolve(choices, maximumProbes: 2, state: { choice in
            if choice.chapterKey == "30" { return .available }
            return Int(choice.chapterKey)! < 20 ? .unavailable : .unknown
        }) { choice in calls.append(choice.chapterKey); return false }
        #expect(calls == ["20", "21"])
        #expect(result?.chapterKey == "30")
    }

    @Test("Offline, sign-in and busy responses stay retryable and do not probe the rest of the book")
    func transientFailureStopsFanout() async {
        let choices = (1...5).map { SumiReaderOpeningPolicy.Choice(chapterKey: "\($0)", startPage: 1, isFirstRead: false) }
        for error in [URLError(.notConnectedToInternet) as Error, HonbakoMangaDexError.requestFailed(401),
                      HonbakoMangaDexError.requestFailed(429), HonbakoMangaDexError.requestFailed(503)] {
            var calls = 0
            do {
                _ = try await SumiReadableOpeningResolver.resolve(choices, state: { _ in .unknown }) { _ in
                    calls += 1
                    throw error
                }
                Issue.record("A temporary source failure must remain retryable")
            } catch { #expect(calls == 1) }
        }
    }

    @Test("The real page-list cache shares fallback evidence with chapter menus and reuses the selected pages")
    func pageCacheAndResolverIntegration() async throws {
        let marker = NSObject()
        let sourceKey = "availability-integration-" + UUID().uuidString
        let cache = SumiChapterPageListCache()
        let choices = ["empty", "readable"].map { SumiReaderOpeningPolicy.Choice(chapterKey: $0, startPage: 1, isFirstRead: true) }
        func key(_ chapter: String) -> SumiChapterPageListCache.Key {
            .init(sourceInstance: ObjectIdentifier(marker), sourceKey: sourceKey, mangaKey: "book", chapterKey: chapter, language: "en")
        }
        let page = AidokuRunner.Page(content: .url(url: URL(string: "https://example.invalid/1.jpg")!))
        var calls: [String] = []
        let result = try await SumiReadableOpeningResolver.resolve(choices, state: { choice in
            HonbakoChapterAvailability.shared.state(for: key(choice.chapterKey))
        }) { choice in
            calls.append(choice.chapterKey)
            let pages = try await cache.pages(for: key(choice.chapterKey)) {
                choice.chapterKey == "empty" ? [] : [page]
            }
            return !pages.isEmpty
        }
        #expect(result?.chapterKey == "readable")
        #expect(calls == ["empty", "readable"])
        #expect(HonbakoChapterAvailability.shared.state(for: key("empty")) == .unavailable)
        #expect(HonbakoChapterAvailability.shared.state(for: key("readable")) == .available)
        let staged = try await cache.pages(for: key("readable")) {
            Issue.record("Opening the resolved chapter must reuse its page list")
            return []
        }
        #expect(staged == [page])
        await cache.invalidate(key("empty"))
        #expect(HonbakoChapterAvailability.shared.state(for: key("empty")) == .unknown,
                "An explicit retry must allow a removed or repaired chapter to recover")
        HonbakoChapterAvailability.shared.clear(sourceKey: sourceKey)
    }

    @Test("Cancelling opening never selects another chapter or starts more requests")
    func cancellation() async {
        let choices = [SumiReaderOpeningPolicy.Choice(chapterKey: "1", startPage: 7, isFirstRead: false)]
        let task = Task {
            try await SumiReadableOpeningResolver.resolve(choices, state: { _ in .unknown }) { _ in
                throw CancellationError()
            }
        }
        do { _ = try await task.value; Issue.record("Cancellation must propagate") }
        catch { #expect(error is CancellationError) }
    }
}
