#if SUMI
import AidokuRunner
import Combine
import Foundation
import UserNotifications

@MainActor
final class HonbakoReaderActionsModel: ObservableObject {
    @Published private(set) var isInLibrary = false
    @Published private(set) var hasDownloads = false
    @Published private(set) var notificationsEnabled = true
    @Published private(set) var notificationsAuthorized = false
    @Published private(set) var busy = false
    @Published var message: String?
    let manga: AidokuRunner.Manga
    let chapter: AidokuRunner.Chapter
    let chapters: [AidokuRunner.Chapter]

    init(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter, chapters: [AidokuRunner.Chapter]) {
        self.manga = manga
        self.chapter = chapter
        self.chapters = chapters
    }

    func refresh() async {
        let identifier = manga.identifier
        isInLibrary = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.hasLibraryManga(mangaId: identifier, context: context)
        }
        hasDownloads = await DownloadManager.shared.hasDownloadedChapter(from: manga.identifier)
        notificationsEnabled = HonbakoChapterAlerts.preferenceEnabled(for: manga.identifier)
        let permission = await NotificationManager.shared.authorizationStatus()
        notificationsAuthorized = permission == .authorized || permission == .provisional || permission == .ephemeral
    }

    func toggleLibrary() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if isInLibrary {
            await MangaManager.shared.removeFromLibrary(mangaIds: [manga.identifier])
        } else {
            var payload = manga
            payload.chapters = chapters
            await MangaManager.shared.addToLibrary(manga: payload, chapters: chapters)
            await HonbakoChapterAlerts.shared.didAddToLibrary(manga.identifier)
        }
        await refresh()
    }

    func download(all: Bool) async {
        guard !busy, HonbakoProStore.shared.hasPro else { return }
        busy = true
        defer { busy = false }
        let chosen = all ? chapters.filter { !$0.locked } : [chapter].filter { !$0.locked }
        guard !chosen.isEmpty else { message = "This source has no downloadable chapters."; return }
        var payload = manga
        payload.chapters = chapters
        await DownloadManager.shared.download(manga: payload, chapters: all ? Array(chosen.reversed()) : chosen)
        message = all ? "Chapters queued for offline reading." : "This chapter is queued for offline reading."
        await refresh()
    }

    func removeDownloads() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        // Storage removal stays available when a Pro entitlement expires.
        await DownloadManager.shared.cancelDownloads(for: chapters.map {
            ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: $0.key)
        })
        await DownloadManager.shared.deleteChapters(for: manga.identifier)
        message = "Offline copies removed."
        await refresh()
    }

    func setNotifications(_ enabled: Bool) async {
        guard isInLibrary, HonbakoProStore.shared.hasPro else { return }
        await HonbakoChapterAlerts.shared.setEnabled(enabled, for: manga.identifier)
        notificationsEnabled = HonbakoChapterAlerts.preferenceEnabled(for: manga.identifier)
        let permission = await NotificationManager.shared.authorizationStatus()
        notificationsAuthorized = permission == .authorized || permission == .provisional || permission == .ephemeral
        if enabled, permission == .denied {
            message = "Allow notifications for Honbako in System Settings to receive chapter alerts."
        }
    }
}
#endif
