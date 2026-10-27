#if SUMI
import AidokuRunner
import UIKit

@MainActor
enum HonbakoEarlierChapterPrompt {
    private static var handled: Set<ChapterIdentifier> = []
    private static var inFlight: Set<ChapterIdentifier> = []

    static func recordDecision(mangaID: MangaIdentifier, chapterKey: String) {
        let id = ChapterIdentifier(sourceKey: mangaID.sourceKey, mangaKey: mangaID.mangaKey, chapterKey: chapterKey)
        handled.insert(id)
        if handled.count > 256 { handled = [id] }
    }

    static func consider(manga: AidokuRunner.Manga, selected: AidokuRunner.Chapter,
                         chapters: [AidokuRunner.Chapter], presenter: UIViewController,
                         whileCurrent: @escaping @MainActor () -> Bool,
                         historyLoader: (@Sendable (MangaIdentifier) async -> Set<String>)? = nil) async {
        guard !Task.isCancelled, whileCurrent(), !AppSettings.general.incognitoMode.get(),
              presenter.presentedViewController == nil else { return }
        let id = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: selected.key)
        guard !handled.contains(id), inFlight.insert(id).inserted else { return }
        defer { inFlight.remove(id) }
        let completed: Set<String>
        if let historyLoader { completed = await historyLoader(manga.identifier) }
        else {
            completed = await CoreDataManager.shared.container.performBackgroundTask { context in
                Set(CoreDataManager.shared.getHistoryForManga(mangaId: manga.identifier, context: context)
                    .filter(\.completed).map(\.chapterId))
            }
        }
        guard !Task.isCancelled, whileCurrent(), presenter.viewIfLoaded?.window != nil,
              presenter.presentedViewController == nil else { return }
        let earlier = HonbakoEarlierChapterPolicy.unreadBefore(selected, in: chapters, completedKeys: completed)
        recordDecision(mangaID: manga.identifier, chapterKey: selected.key)
        guard !earlier.isEmpty else { return }
        let alert = UIAlertController(title: String(localized: "Mark Earlier Chapters as Read?"),
            message: String(localized: "There are \(earlier.count) earlier unread chapters in this language. Your current chapter stays at its saved position."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Keep Unread"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Mark as Read"), style: .default) { _ in
            Task {
                guard !Task.isCancelled, whileCurrent() else { return }
                await HistoryManager.shared.addHistory(mangaId: manga.identifier, chapters: earlier)
            }
        })
        presenter.present(alert, animated: true)
    }
}
#endif
