@testable import Sumi
import AidokuRunner
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiReaderControlsLifecycleTests {
    @Test("Foreground activation preserves visible controls and restores their status presentation")
    func foregroundKeepsVisibleControls() throws {
        try withReader { reader, scene in
            reader.showBars()
            #expect(!reader.barsHidden)
            #expect(reader.navigationController?.isNavigationBarHidden == false)
            let center = NotificationCenter.default
            center.post(name: UIScene.willDeactivateNotification, object: scene)
            center.post(name: UIScene.willEnterForegroundNotification, object: scene)
            center.post(name: UIScene.didActivateNotification, object: scene)
            #expect(!reader.barsHidden)
            #expect(!reader.prefersStatusBarHidden)

            reader.hideBars()
            #expect(reader.navigationController?.isNavigationBarHidden == true)
            center.post(name: UIScene.willDeactivateNotification, object: scene)
            center.post(name: UIScene.willEnterForegroundNotification, object: scene)
            center.post(name: UIScene.didActivateNotification, object: scene)
            #expect(reader.barsHidden, "Foreground must also preserve an explicit hide")
            #expect(reader.prefersStatusBarHidden)
        }
    }

    @Test("Unowned scene lifecycle notifications cannot hide or alter the reader controls")
    func unownedActivationKeepsControls() throws {
        try withReader { reader, _ in
            reader.showBars()
            for name in [UIScene.willDeactivateNotification, UIScene.willEnterForegroundNotification, UIScene.didActivateNotification] {
                NotificationCenter.default.post(name: name, object: nil)
                #expect(!reader.barsHidden)
                #expect(!reader.prefersStatusBarHidden)
            }
            reader.toggleBarVisibility()
            #expect(reader.barsHidden)
            reader.toggleBarVisibility()
            #expect(!reader.barsHidden)
        }
    }

    private func withReader(_ check: (ReaderViewController, UIWindowScene) throws -> Void) throws {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var values = original
        values["General.incognitoMode"] = true
        values["Reader.liveText"] = false
        defaults.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        let reader = ReaderViewController(source: nil,
            manga: AidokuRunner.Manga(sourceKey: "sumi-controls-lifecycle-test", key: "book", title: "Toolbar lifecycle"),
            chapter: .init(key: "first"), startPage: 1)
        reader.sumiIsPreparingOpening = true
        let container = SumiDirectReaderController(content: reader)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = container
        window.isHidden = false
        container.loadViewIfNeeded()
        reader.loadViewIfNeeded()
        reader.sumiIsPreparingOpening = false
        defer {
            reader.sumiIsPreparingOpening = true
            window.isHidden = true
            window.rootViewController = nil
        }
        try check(reader, scene)
    }
}
