//
//  ChapterNotificationTests.swift
//  AidokuTests
//

@testable import Aidoku
import AidokuRunner
import Foundation
import Testing
import UserNotifications

struct ChapterNotificationTests {
    @Test("Chapter alerts require both language and scanlator matches and readable chapters")
    func chapterFilters() {
        let chapters = [
            chapter("matching"), chapter("wrong-language", language: "ja"),
            chapter("wrong-group", scanlator: "Other"), chapter("locked", locked: true)
        ]
        #expect(ChapterNotificationPolicy.eligibleChapterKeys(
            chapters, hasExistingChapters: true, languageFilter: "en", scanlatorFilter: ["Group"]
        ) == ["matching"])
        #expect(ChapterNotificationPolicy.eligibleChapterKeys(
            chapters, hasExistingChapters: true, languageFilter: nil, scanlatorFilter: []
        ) == ["matching", "wrong-group", "wrong-language"])
    }

    @Test("An initial chapter fetch establishes a baseline without a backlog alert")
    func firstFetchBaseline() {
        #expect(ChapterNotificationPolicy.eligibleChapterKeys(
            [chapter("1"), chapter("2")], hasExistingChapters: false, languageFilter: nil, scanlatorFilter: []
        ).isEmpty)
        #expect(ChapterNotificationPolicy.eligibleChapterKeys(
            [chapter("3"), chapter("3")], hasExistingChapters: true, languageFilter: nil, scanlatorFilter: []
        ) == ["3"])
    }

    @Test("A selected scanlator matches a collaborative release and uncredited releases stay selectable")
    func collaborativeAndUncreditedChapterFilters() {
        let collaborative = AidokuRunner.Chapter(key: "collaboration", scanlators: ["Group", "Partner"], language: "en")
        let uncredited = AidokuRunner.Chapter(key: "uncredited", language: "en")
        #expect(ChapterNotificationPolicy.matchesFilters(collaborative, languageFilter: "en", scanlatorFilter: ["Partner"]))
        #expect(!ChapterNotificationPolicy.matchesFilters(collaborative, languageFilter: "ja", scanlatorFilter: ["Partner"]))
        #expect(ChapterNotificationPolicy.eligibleChapterKeys(
            [collaborative, uncredited], hasExistingChapters: true, languageFilter: "en", scanlatorFilter: ["Partner", ""]
        ) == ["collaboration", "uncredited"])
        #expect(!ChapterNotificationPolicy.matchesFilters(uncredited, languageFilter: nil, scanlatorFilter: ["Partner"]))
    }

    @Test("Notification identity is canonical across repeated encodes, input order, titles, and duplicate chapter keys")
    func canonicalNotificationIdentity() throws {
        let first = summary("series", keys: ["2", "1", "1"])
        let other = summary("other-series", source: "other-source", keys: ["1"])
        let equivalent = ChapterNotificationSummary(mangaIdentifier: first.mangaIdentifier, mangaTitle: "Renamed", chapterKeys: ["1", "2"])
        let expected = ChapterNotificationSummary.notificationIdentifier(for: [first, other])
        for _ in 0..<20 {
            let restored = try JSONDecoder().decode([ChapterNotificationSummary].self, from: JSONEncoder().encode([other, equivalent]))
            #expect(ChapterNotificationSummary.notificationIdentifier(for: restored) == expected)
        }
        #expect(ChapterNotificationSummary.notificationIdentifier(for: [summary("series", keys: ["3"]), other]) != expected)
    }

    @Test("Persistent chapter deduplication keeps source and manga identities separate")
    func persistentQueue() throws {
        let first = summary("series", keys: ["1", "1", "2"])
        let other = summary("series", source: "other-source", keys: ["1"])
        var queue = ChapterNotificationQueue()
        queue.enqueue([first, other])
        #expect(queue.pending.count == 2)
        #expect(queue.pending.map(\.chapterCount).reduce(0, +) == 3)
        queue.markDelivered([summary("series", keys: ["1"])])

        var restored = try JSONDecoder().decode(ChapterNotificationQueue.self, from: JSONEncoder().encode(queue))
        restored.enqueue([first, other])
        #expect(restored.pending.first { $0.mangaIdentifier == first.mangaIdentifier }?.chapterKeys == ["2"])
        #expect(restored.pending.first { $0.mangaIdentifier == other.mangaIdentifier }?.chapterKeys == ["1"])
        #expect(ChapterNotificationSummary.notificationIdentifier(for: [first, other])
            == ChapterNotificationSummary.notificationIdentifier(for: [other, first]))
    }

    @Test("A failed alert persists and retries after restart without duplicate delivery")
    func failedDeliveryRetries() async throws {
        let fixture = ChapterAlertDeliveryFixture(failures: 1)
        let storage = ChapterAlertStorage()
        let manager = fixture.makeManager(storage: storage)
        let first = summary("series", keys: ["1", "2"])
        await manager.notifyNewChapters([first])
        #expect(await fixture.requests.isEmpty)
        #expect(storage.load()?.pending.count == 1)

        let restarted = fixture.makeManager(queue: try #require(storage.load()), storage: storage)
        await restarted.deliverPendingNotifications()
        await restarted.notifyNewChapters([first])
        #expect(await fixture.requests.count == 1)
        #expect(await fixture.attempts.count == 2)
        #expect(storage.load()?.pending.isEmpty == true)
        #expect(storage.load()?.delivered.count == 2)
        #expect(await fixture.attempts.first == fixture.attempts.last)

        await restarted.notifyNewChapters([summary("series", keys: ["2", "3"])])
        #expect(await fixture.requests.count == 2)
        #expect(storage.load()?.delivered.count == 3)
    }

    @Test("Saved titles survive an interrupted refresh before its batch delivery")
    func perTitleQueueSurvivesInterruption() async throws {
        let fixture = ChapterAlertDeliveryFixture()
        let storage = ChapterAlertStorage()
        let manager = fixture.makeManager(storage: storage)
        for index in 1...4 {
            await manager.enqueueNewChapters([summary("series-\(index)", keys: ["1"])])
            #expect(storage.load()?.pending.count == index)
        }
        #expect(await fixture.attempts.isEmpty)

        // A later source can be interrupted; the next process owns the journal.
        let restarted = fixture.makeManager(queue: try #require(storage.load()), storage: storage)
        await restarted.deliverPendingNotifications()
        #expect(await fixture.requests.count == 1)
        #expect(storage.load()?.pending.isEmpty == true)
        #expect(storage.load()?.delivered.count == 4)
    }

    @Test("Background expiration wins racing completion paths without completing twice")
    func backgroundCompletionAfterExpiration() async {
        let completion = LibraryRefreshTaskCompletion()
        #expect(completion.beginExpiration())
        #expect(!completion.beginExpiration())
        #expect(!completion.mayStart)
        // Only expiration cleanup may complete an expired task, after scheduling.
        #expect(completion.finish() == nil)
        let results = await withTaskGroup(of: Bool?.self, returning: [Bool].self) { group in
            for _ in 0..<32 {
                group.addTask { completion.finish(expiration: true) }
            }
            var results: [Bool] = []
            for await result in group {
                if let result { results.append(result) }
            }
            return results
        }
        #expect(results == [false])
        #expect(completion.isCompleted)

        let completed = LibraryRefreshTaskCompletion()
        #expect(completed.mayStart)
        #expect(completed.finish() == true)
        #expect(!completed.mayStart)
        #expect(!completed.beginExpiration())
        #expect(completed.finish() == nil)
    }

    @Test("Concurrent refresh callbacks enqueue each chapter only once")
    func concurrentDelivery() async {
        let fixture = ChapterAlertDeliveryFixture()
        let manager = fixture.makeManager()
        let item = summary("series", keys: ["1"])
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { await manager.notifyNewChapters([item]) }
            }
        }
        #expect(await fixture.requests.count == 1)
        #expect(await fixture.attempts.count == 1)
    }

    @Test("Denied notification permission queues an alert without prompting or sending")
    func permissionIsNotRequestedByRefresh() async {
        let fixture = ChapterAlertDeliveryFixture(status: .denied)
        let storage = ChapterAlertStorage()
        let manager = fixture.makeManager(storage: storage)
        await manager.notifyNewChapters([summary("series", keys: ["1"])])
        #expect(await fixture.attempts.isEmpty)
        #expect(storage.load()?.pending.count == 1)
        await fixture.setStatus(.authorized)
        await manager.deliverPendingNotifications()
        #expect(await fixture.requests.count == 1)
    }

    @Test("A removed library title is discarded before a pending alert is delivered")
    func onlySavedTitles() async {
        let removed = summary("removed", keys: ["1"])
        let fixture = ChapterAlertDeliveryFixture(removed: [removed.mangaIdentifier])
        let storage = ChapterAlertStorage()
        let manager = fixture.makeManager(storage: storage)
        await manager.notifyNewChapters([removed])
        #expect(await fixture.requests.isEmpty)
        #expect(storage.load()?.pending.isEmpty == true)
    }

    @Test("Many updated library titles produce one batch alert")
    func batchDelivery() async {
        let fixture = ChapterAlertDeliveryFixture()
        let manager = fixture.makeManager()
        await manager.notifyNewChapters((1...4).map { summary("series-\($0)", keys: ["1"]) })
        #expect(await fixture.requests.count == 1)
        #expect(await fixture.requests.first?.content.threadIdentifier == NotificationManager.threadIdentifier)
    }

    @Test("Notification links preserve a source's slash-containing manga key")
    func mangaDeepLink() throws {
        let key = "/series/01J76XY7KT7J224EBK6J816Y1Q/Onepunch-Man"
        let url = try #require(NotificationManager.mangaURL(sourceKey: "en.weebcentral", mangaKey: key))
        #expect(url.host == "en.weebcentral")
        let components = url.percentEncodedPath.split(separator: "/")
        #expect(components.count == 1)
        #expect(String(components[0]).removingPercentEncoding == key)
    }

    private func chapter(_ key: String, language: String = "en", scanlator: String = "Group", locked: Bool = false) -> AidokuRunner.Chapter {
        .init(key: key, scanlators: [scanlator], language: language, locked: locked)
    }

    private func summary(_ manga: String, source: String = "test-source", keys: [String]) -> ChapterNotificationSummary {
        .init(mangaIdentifier: .init(sourceKey: source, mangaKey: manga), mangaTitle: manga, chapterKeys: keys)
    }
}

private actor ChapterAlertDeliveryFixture {
    private enum Failure: Error { case unavailable }
    private var status: UNAuthorizationStatus
    private var failures: Int
    private let removed: Set<MangaIdentifier>
    private(set) var requests: [UNNotificationRequest] = []
    private(set) var attempts: [String] = []

    init(status: UNAuthorizationStatus = .authorized, failures: Int = 0, removed: Set<MangaIdentifier> = []) {
        self.status = status
        self.failures = failures
        self.removed = removed
    }

    nonisolated func makeManager(queue: ChapterNotificationQueue = .init(), storage: ChapterAlertStorage = .init()) -> NotificationManager {
        NotificationManager(queue: queue, delivery: .init(
            enabled: { true },
            authorizationStatus: { await self.status },
            isInLibrary: { await !self.removed.contains($0) },
            send: { try await self.send($0) },
            persist: { storage.save($0) }
        ))
    }

    func setStatus(_ status: UNAuthorizationStatus) { self.status = status }

    private func send(_ request: UNNotificationRequest) async throws {
        attempts.append(request.identifier)
        if failures > 0 {
            failures -= 1
            throw Failure.unavailable
        }
        await Task.yield()
        requests.append(request)
    }
}

private final class ChapterAlertStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    func save(_ queue: ChapterNotificationQueue) {
        lock.lock()
        defer { lock.unlock() }
        data = try? JSONEncoder().encode(queue)
    }

    func load() -> ChapterNotificationQueue? {
        lock.lock()
        defer { lock.unlock() }
        return data.flatMap { try? JSONDecoder().decode(ChapterNotificationQueue.self, from: $0) }
    }
}
