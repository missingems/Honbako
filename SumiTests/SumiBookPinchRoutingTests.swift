@testable import Sumi
import AidokuRunner
import Testing
import UIKit

@MainActor
struct SumiBookPinchRoutingTests {
    @Test("A presented reader observes both page and native-bar touches at the window and removes that gesture on dismissal")
    func windowGestureLifetime() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        let content = UIViewController()
        let navigation = SumiDirectReaderController(content: content)
        navigation.modalPresentationStyle = .overFullScreen
        let transition = SumiBookTransition(coverImage: nil, readerSurface: { content.view },
            paired: { false }, sourceView: { nil })
        navigation.bookTransition = transition
        transition.install(on: navigation)
        let pinch = try #require(transition.pinch)
        #expect(pinch.view === navigation.view, "A staged reader must not intercept another window")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            presenter.present(navigation, animated: false) { continuation.resume() }
        }
        #expect(pinch.view === window, "The app window also contains an adaptively hosted native toolbar")
        #expect(window.gestureRecognizers?.contains { $0 === pinch } == true)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            navigation.dismiss(animated: false) { continuation.resume() }
        }
        #expect(pinch.view == nil)
        #expect(window.gestureRecognizers?.contains { $0 === pinch } != true)
        #expect(navigation.bookTransition == nil)
    }

    @Test("Book pinch owns two touches while native page and vertical pans keep one-finger scrolling")
    func touchOwnership() throws {
        let content = UIViewController()
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        content.view.addSubview(scroll)
        let nested = UIScrollView(frame: scroll.bounds)
        scroll.addSubview(nested)
        let navigation = SumiDirectReaderController(content: content)
        let transition = SumiBookTransition(coverImage: nil, readerSurface: { scroll },
            paired: { false }, sourceView: { nil })
        transition.install(on: navigation)
        let pinch = try #require(transition.pinch)
        let edge = try #require(transition.edgeSwipe)
        #expect(pinch.cancelsTouchesInView, "A recognized pinch cancels any reader button tracking")
        #expect(!pinch.delaysTouchesBegan, "One-finger reader controls stay immediate")
        #expect(scroll.panGestureRecognizer.maximumNumberOfTouches == 1)
        #expect(nested.panGestureRecognizer.maximumNumberOfTouches == 1)
        #expect(scroll.panGestureRecognizer.isEnabled)
        #expect(transition.gestureRecognizer(pinch, shouldRecognizeSimultaneouslyWith: scroll.panGestureRecognizer),
                "A one-page finger cannot prevent the window's two-touch pinch from starting")
        #expect(transition.gestureRecognizer(scroll.panGestureRecognizer, shouldRecognizeSimultaneouslyWith: pinch))
        #expect(transition.gestureRecognizer(edge, shouldRecognizeSimultaneouslyWith: scroll.panGestureRecognizer))
    }

    @Test("An active book pinch suspends owned page and toolbar pans and restores only their prior enabled states")
    func ownedPansSuspendAndRestore() {
        let window = UIWindow()
        let page = UIScrollView()
        let toolbarHost = UIView()
        let toolbar = UIView()
        let strip = UIScrollView()
        window.addSubview(page)
        window.addSubview(toolbarHost)
        toolbarHost.addSubview(toolbar)
        toolbar.addSubview(strip)
        let hostPan = UIPanGestureRecognizer()
        toolbarHost.addGestureRecognizer(hostPan)
        let disabledPan = UIPanGestureRecognizer()
        disabledPan.isEnabled = false
        toolbar.addGestureRecognizer(disabledPan)
        let edge = UIScreenEdgePanGestureRecognizer()
        page.addGestureRecognizer(edge)
        let systemPan = UIPanGestureRecognizer()
        window.addGestureRecognizer(systemPan)
        let suspension = SumiBookPanSuspension()
        suspension.suspend(in: [page, toolbar], includingAncestorsOf: [toolbar], excluding: edge)
        #expect(!page.panGestureRecognizer.isEnabled)
        #expect(!strip.panGestureRecognizer.isEnabled)
        #expect(!hostPan.isEnabled)
        #expect(!disabledPan.isEnabled)
        #expect(edge.isEnabled)
        #expect(systemPan.isEnabled, "Window and system gestures are never suspended")
        suspension.suspend(in: [page, toolbar], includingAncestorsOf: [toolbar], excluding: edge)
        suspension.restore()
        #expect(page.panGestureRecognizer.isEnabled)
        #expect(strip.panGestureRecognizer.isEnabled)
        #expect(hostPan.isEnabled)
        #expect(!disabledPan.isEnabled)
        suspension.restore()
        #expect(!disabledPan.isEnabled)
    }

    @Test("Interrupting a native portrait turn restores the settled page and ignores its late completion")
    func interruptedNativeTurnCannotCommitAfterCloseBegins() async throws {
        let temporaryPages = ReaderTemporaryPageStore()
        defer { Task { await temporaryPages.removeAll() } }
        let chapter = AidokuRunner.Chapter(key: "pinch-interruption")
        let manga = AidokuRunner.Manga(sourceKey: "sumi-pinch-test", key: "book", title: "Pinch")
        let reader = ReaderPagedViewController(source: nil, manga: manga, temporaryPageStore: temporaryPages)
        reader.chapter = chapter
        reader.loadViewIfNeeded()
        reader.view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        reader.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600)).image { output in
            UIColor.white.setFill()
            output.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
        }
        reader.viewModel.pages = (0..<3).map {
            .init(sourceId: manga.sourceKey, chapterId: chapter.id, index: $0, image: image)
        }
        reader.loadPageControllers(chapter: chapter)
        reader.loadPages(in: 1...3)
        reader.move(toPage: 1, animated: false)
        let original = try #require(reader.children.compactMap { $0 as? UIPageViewController }.first)
        #expect(original.transitionStyle == .scroll)
        let second = try #require(reader.pageViewControllers.filter { controller in
            if case .page = controller.type { return true }
            return false
        }.dropFirst().first)
        reader.pageViewController(original, willTransitionTo: [second])
        original.setViewControllers([second], direction: .forward, animated: false)
        reader.sumiStopAnimatedNavigation()
        let settled = try #require(reader.children.compactMap { $0 as? UIPageViewController }.first)
        #expect(settled !== original)
        #expect(reader.currentPage == 1)
        reader.pageViewController(original, didFinishAnimating: true, previousViewControllers: [], transitionCompleted: true)
        #expect(reader.currentPage == 1, "An abandoned native slide cannot land a different page while the book is closing")
        let pans = settled.view.subviews.compactMap { $0 as? UIScrollView }.map(\.panGestureRecognizer)
        #expect(!pans.isEmpty)
        #expect(pans.allSatisfy { $0.maximumNumberOfTouches == 1 })
    }
}
