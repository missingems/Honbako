//
//  NotificationManager.swift
//  Aidoku
//

import Foundation
import UserNotifications

actor NotificationManager {
    static let shared = NotificationManager()
    typealias NewChaptersSummary = ChapterNotificationSummary

    struct Delivery: Sendable {
        var enabled: @Sendable () -> Bool
        var authorizationStatus: @Sendable () async -> UNAuthorizationStatus
        var isInLibrary: @Sendable (MangaIdentifier) async -> Bool
        var send: @Sendable (UNNotificationRequest) async throws -> Void
        var persist: @Sendable (ChapterNotificationQueue) -> Void

        static var live: Self {
            .init(
                enabled: { AppSettings.library.notifyNewChapters.get() },
                authorizationStatus: { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus },
                isInLibrary: { mangaId in
                    #if SUMI
                    guard HonbakoChapterAlerts.preferenceEnabled(for: mangaId),
                          await MainActor.run(body: { HonbakoProStore.shared.hasPro }) else { return false }
                    #endif
                    return await CoreDataManager.shared.container.performBackgroundTask { context in
                        CoreDataManager.shared.getLibraryManga(mangaId: mangaId, context: context) != nil
                    }
                },
                send: { try await UNUserNotificationCenter.current().add($0) },
                persist: { queue in
                    if let data = try? JSONEncoder().encode(queue) {
                        UserDefaults.standard.set(data, forKey: NotificationManager.queueKey)
                    }
                }
            )
        }
    }

    static let categoryIdentifier = "newChapters"
    static let threadIdentifier = "newChapters"
    static let sourceIdInfoKey = "sourceId"
    static let mangaIdInfoKey = "mangaId"
    static let batchNotificationThreshold = 3
    private static let queueKey = "Library.chapterNotificationQueue"

    private let delivery: Delivery
    private var queue: ChapterNotificationQueue
    private var isDelivering = false

    init(queue: ChapterNotificationQueue? = nil, delivery: Delivery = .live) {
        self.delivery = delivery
        self.queue = queue ?? UserDefaults.standard.data(forKey: Self.queueKey)
            .flatMap { try? JSONDecoder().decode(ChapterNotificationQueue.self, from: $0) } ?? .init()
    }

    nonisolated func isEnabled() -> Bool {
        delivery.enabled()
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await delivery.authorizationStatus()
    }

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                return true
            case .notDetermined:
                return (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            default:
                return false
        }
    }

    func notifyNewChapters(_ summaries: [NewChaptersSummary]) async {
        enqueueNewChapters(summaries)
        await deliverPendingNotifications()
    }

    /// Journal each saved title before the refresh starts another source request.
    /// Delivery stays separate so a complete refresh can still produce one batch.
    func enqueueNewChapters(_ summaries: [NewChaptersSummary]) {
        guard !summaries.isEmpty, isEnabled() else { return }
        queue.enqueue(summaries)
        delivery.persist(queue)
    }

    func clearPendingNotifications() {
        queue.clearPending()
        delivery.persist(queue)
    }

    func deliverPendingNotifications() async {
        guard !isDelivering, isEnabled(), !queue.pending.isEmpty else { return }
        isDelivering = true
        defer { isDelivering = false }
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        while isEnabled(), !queue.pending.isEmpty {
            var summaries: [NewChaptersSummary] = []
            for summary in queue.pending {
                if await delivery.isInLibrary(summary.mangaIdentifier) {
                    summaries.append(summary)
                } else {
                    queue.discard(mangaIdentifier: summary.mangaIdentifier)
                    delivery.persist(queue)
                }
            }
            guard isEnabled(), !summaries.isEmpty else { return }
            let batch = summaries.count > Self.batchNotificationThreshold
            let delivered = batch ? summaries : [summaries[0]]
            let request = Self.request(for: delivered, batch: batch)
            do {
                try await delivery.send(request)
                queue.markDelivered(delivered)
                delivery.persist(queue)
            } catch {
                // Keep the same stable request and chapter identities for the next retry.
                LogManager.logger.error("Could not deliver new chapter notification: \(error)")
                return
            }
        }
    }

    nonisolated static func mangaURL(sourceKey: String, mangaKey: String) -> URL? {
        let pathCharacters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/%?#"))
        guard let source = sourceKey.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let manga = mangaKey.addingPercentEncoding(withAllowedCharacters: pathCharacters) else { return nil }
        return URL(string: "aidoku://\(source)/\(manga)")
    }

    private static func request(for summaries: [NewChaptersSummary], batch: Bool) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        if batch {
            content.title = NSLocalizedString("NEW_CHAPTERS_AVAILABLE")
            content.body = String(format: NSLocalizedString("X_SERIES_HAVE_NEW_CHAPTERS"), summaries.count)
        } else if let summary = summaries.first {
            content.title = summary.mangaTitle
            content.body = summary.chapterCount == 1
                ? NSLocalizedString("1_NEW_CHAPTER_AVAILABLE")
                : String(format: NSLocalizedString("X_NEW_CHAPTERS_AVAILABLE"), summary.chapterCount)
            content.userInfo = [
                sourceIdInfoKey: summary.mangaIdentifier.sourceKey,
                mangaIdInfoKey: summary.mangaIdentifier.mangaKey
            ]
        }
        content.sound = .default
        content.threadIdentifier = threadIdentifier
        content.categoryIdentifier = categoryIdentifier
        return UNNotificationRequest(
            identifier: NewChaptersSummary.notificationIdentifier(for: summaries), content: content, trigger: nil
        )
    }
}
