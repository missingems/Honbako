@testable import Sumi
import AidokuRunner
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct HonbakoEarlierChapterPromptTests {
    private actor DeferredHistory {
        private var continuation: CheckedContinuation<Set<String>, Never>?
        private var released = false
        private(set) var started = false

        func load() async -> Set<String> {
            started = true
            if released { return [] }
            return await withCheckedContinuation { continuation = $0 }
        }

        func release() {
            released = true
            continuation?.resume(returning: [])
            continuation = nil
        }
    }

    @Test("A chapter change during the history fetch cannot present an obsolete prompt or consume the next valid attempt")
    func chapterChangeDuringHistoryFetch() async throws {
        let defaults = UserDefaults.standard
        let key = AppSettings.general.incognitoMode.key
        let previousIncognito = defaults.object(forKey: key)
        defaults.set(false, forKey: key)
        defer { defaults.set(previousIncognito, forKey: key) }

        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        presenter.loadViewIfNeeded()
        defer {
            presenter.dismiss(animated: false)
            let wasKey = window.isKeyWindow
            window.isHidden = true
            window.rootViewController = nil
            if wasKey { previousWindow?.makeKey() }
        }

        let manga = AidokuRunner.Manga(sourceKey: "prompt-test", key: UUID().uuidString, title: "Test")
        let selected = AidokuRunner.Chapter(key: "chapter-20", chapterNumber: 20)
        let earlier = AidokuRunner.Chapter(key: "chapter-19", chapterNumber: 19)
        let history = DeferredHistory()
        var isCurrent = true
        let task = Task {
            await HonbakoEarlierChapterPrompt.consider(manga: manga, selected: selected,
                chapters: [selected, earlier], presenter: presenter,
                whileCurrent: { isCurrent }, historyLoader: { _ in await history.load() })
        }
        defer {
            task.cancel()
            Task { await history.release() }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await history.started), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(await history.started)
        isCurrent = false
        await history.release()
        await task.value
        #expect(presenter.presentedViewController == nil)

        isCurrent = true
        await HonbakoEarlierChapterPrompt.consider(manga: manga, selected: selected,
            chapters: [selected, earlier], presenter: presenter,
            whileCurrent: { isCurrent }, historyLoader: { _ in [] })
        #expect(presenter.presentedViewController is UIAlertController)
    }
}
