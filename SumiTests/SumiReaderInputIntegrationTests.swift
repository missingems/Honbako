@testable import Sumi
import AidokuRunner
import AsyncDisplayKit
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiReaderInputIntegrationTests {
    @Test("The source selects book or vertical scrolling despite legacy per-book overrides")
    func sourceModeWins() throws {
        let defaults = UserDefaults.standard
        let saved = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(saved, forName: UserDefaults.argumentDomain) }
        for (viewer, expected) in [(Viewer.vertical, ReadingMode.continuous), (.webtoon, .webtoon),
                                   (.leftToRight, .ltr), (.rightToLeft, .rtl)] {
            let manga = AidokuRunner.Manga(sourceKey: "sumi-input-test", key: "viewer-\(viewer.rawValue)",
                                          title: "Source reader", viewer: viewer)
            var values = saved
            values["General.incognitoMode"] = true
            values["Reader.readingMode"] = "rtl"
            values["Reader.readingMode.\(manga.identifier)"] = "rtl"
            defaults.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
            let reader = ReaderViewController(source: nil, manga: manga, chapter: .init(key: "first"), startPage: 1)
            reader.sumiIsPreparingOpening = true
            reader.loadViewIfNeeded()
            #expect(reader.readingMode == expected)
            if expected == .webtoon || expected == .continuous {
                let scroll = try #require(reader.reader as? ReaderWebtoonViewController)
                #expect(scroll.readingMode == expected)
                #expect(scroll.scrollView.maximumZoomScale == 1)
                #expect(!scroll.zoomView.doubleTapEnabled)
            } else {
                #expect(reader.reader is ReaderPagedViewController)
            }
            reader.viewWillDisappear(false)
            #expect(reader.sumiPendingHistorySave == nil)
            reader.sumiIsPreparingOpening = false
            reader.setChapter(.init(key: "second"))
            reader.setChapter(.init(key: "third"))
            reader.viewWillDisappear(false)
            #expect(reader.sumiPendingHistorySave == nil,
                    "Chapters selected before a page appears must not create bookmarks")
        }
    }

    @Test("An opened vertical reader routes touches to its real scrolling surface")
    func openedVerticalTouchRouting() async throws {
        let defaults = UserDefaults.standard
        let saved = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var values = saved
        values["General.incognitoMode"] = true
        defaults.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(saved, forName: UserDefaults.argumentDomain) }
        let chapter = AidokuRunner.Chapter(key: "touch")
        let reader = ReaderViewController(source: nil,
            manga: .init(sourceKey: "sumi-input-test", key: "touch", title: "Touch", viewer: .webtoon),
            chapter: chapter, startPage: 1)
        reader.sumiIsPreparingOpening = true
        let container = SumiDirectReaderController(content: UIViewController())
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = container
        window.isHidden = false
        container.show(reader)
        defer { reader.sumiIsPreparingOpening = true; window.isHidden = true; window.rootViewController = nil }
        let scroll = try #require(reader.reader as? ReaderWebtoonViewController)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
        }
        scroll.viewModel.sumiPageLoaderOverride = { selected in
            (0..<8).map { .init(sourceId: "sumi-input-test", chapterId: selected.id, index: $0, image: image) }
        }
        scroll.setChapter(chapter, startPage: 1)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !scroll.sumiReadyForOpening, ContinuousClock.now < deadline {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(scroll.sumiReadyForOpening)
        reader.sumiDidOpenPreparedBook()
        window.layoutIfNeeded()
        #expect(scroll.scrollView.isScrollEnabled)
        #expect(scroll.scrollView.panGestureRecognizer.isEnabled)
        var hit = reader.view.hitTest(CGPoint(x: reader.view.bounds.width * 0.45,
                                             y: reader.view.bounds.height * 0.8), with: nil)
        var reachesScrollView = false
        var hitPath: [String] = []
        while let candidate = hit {
            hitPath.append(String(describing: type(of: candidate)))
            if candidate === scroll.scrollView { reachesScrollView = true }
            hit = candidate.superview
        }
        #expect(reachesScrollView, "Touch path must include native scrolling surface: \(hitPath)")
        scroll.sumiMove(toCanonicalPage: 3)
        #expect(reader.view.accessibilityValue == "Chapter, page 3")
    }

    @Test("Reader keyboard commands expose reading actions and yield to a presented sheet")
    func keyboardCommandsYieldToSheets() async throws {
        let defaults = UserDefaults.standard
        let saved = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var values = saved
        values["General.incognitoMode"] = true
        defaults.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(saved, forName: UserDefaults.argumentDomain) }
        let reader = ReaderViewController(source: nil,
            manga: .init(sourceKey: "sumi-input-test", key: "keyboard", title: "Keyboard"),
            chapter: .init(key: "first"), startPage: 1)
        reader.sumiIsPreparingOpening = true
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = reader
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        #expect(reader.keyCommands == nil)
        reader.sumiIsPreparingOpening = false
        let commands = try #require(reader.keyCommands)
        #expect(commands.contains { $0.input == UIKeyCommand.inputLeftArrow })
        #expect(commands.contains { $0.input == UIKeyCommand.inputRightArrow })
        #expect(commands.contains { $0.input == UIKeyCommand.inputDownArrow })
        #expect(commands.contains { $0.input == UIKeyCommand.inputUpArrow })
        #expect(commands.contains { $0.input == " " && $0.modifierFlags.isEmpty })
        #expect(commands.contains { $0.input == " " && $0.modifierFlags == .shift })
        #expect(commands.contains { $0.input == "l" && $0.modifierFlags == .command })
        #expect(commands.contains { $0.input == "w" && $0.modifierFlags == .command })
        #expect(commands.contains { $0.input == UIKeyCommand.inputEscape })
        #expect(!commands.contains { $0.action == #selector(ReaderViewController.toggleOffset) })
        #expect(!commands.contains { ($0.action.map(NSStringFromSelector) ?? "").localizedCaseInsensitiveContains("settings") })
        #expect(commands.allSatisfy { !$0.wantsPriorityOverSystemBehavior })
        let sheet = UIViewController()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            reader.present(sheet, animated: false) { continuation.resume() }
        }
        #expect(reader.presentedViewController === sheet)
        #expect(reader.keyCommands == nil)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            reader.dismiss(animated: false) { continuation.resume() }
        }
        #expect(reader.keyCommands?.count == commands.count)
        reader.sumiIsPreparingOpening = true
    }
}
