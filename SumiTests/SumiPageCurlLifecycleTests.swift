@testable import Sumi
import AidokuRunner
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiPageCurlLifecycleTests {
    private func page(_ color: UIColor) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = color
        return controller
    }

    @Test("Portrait gestures and source-aware toolbar commands advance the same canonical page")
    func portraitCanonicalNavigation() throws {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var settings = original
        settings["Reader.pagedPageLayout"] = "auto"
        settings["Reader.splitWideImages"] = false
        settings["Reader.animatePageTransitions"] = false
        defaults.setVolatileDomain(settings, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        let store = ReaderTemporaryPageStore()
        defer { Task { await store.removeAll() } }
        for readingMode in [ReadingMode.ltr, .rtl] {
            let reader = ReaderPagedViewController(source: nil,
                manga: .init(sourceKey: "sumi-test", key: "portrait", title: "Portrait"), temporaryPageStore: store)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 650, height: 1000))
            window.rootViewController = reader
            window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            reader.readingMode = readingMode
            let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600)).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
            }
            reader.viewModel.pages = (0..<4).map {
                .init(sourceId: "sumi-test", chapterId: "portrait", index: $0, image: image)
            }
            reader.loadPageControllers(chapter: .init(key: "portrait"))
            reader.loadPages(in: 1...4)
            reader.view.layoutIfNeeded()
            reader.move(toPage: 1, animated: false)
            let pager = try #require(reader.children.compactMap { $0 as? UIPageViewController }.first)
            #expect(!(pager is SumiPageCurlViewController))
            #expect(pager.transitionStyle == .scroll)
            #expect(pager.view.accessibilityIdentifier == "sumi.reader.slide")
            let current = try #require(pager.viewControllers?.first)
            let next = reader.pageViewController(pager, viewControllerAfter: current)
            #expect(next === reader.pageViewControllers[2])
            if readingMode == .rtl { reader.moveLeft() } else { reader.moveRight() }
            #expect(reader.currentPage == 2)
            #expect(reader.pageViewController(pager, viewControllerBefore: reader.pageViewControllers[2])
                    === reader.pageViewControllers[1])
            if readingMode == .rtl { reader.moveRight() } else { reader.moveLeft() }
            #expect(reader.currentPage == 1)
        }
    }

    @Test("Settle easing starts and finishes gently with a faster middle")
    func settleEasing() {
        let start = SumiPageCurlJourneyTimeline.easedProgress(0.1)
        let middle = SumiPageCurlJourneyTimeline.easedProgress(0.5)
        let end = SumiPageCurlJourneyTimeline.easedProgress(0.9)
        #expect(start < 0.1)
        #expect(middle == 0.5)
        #expect(end > 0.9)
        #expect(abs(start - (1 - end)) < 0.00001)
    }

    @Test("A leaf sheds its binding light in portrait and restores it on returning to the spread")
    func bindingLightingReparent() {
        let store = ReaderTemporaryPageStore()
        defer { Task { await store.removeAll() } }
        let first = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: store)
        let canonical = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: store)
        let wide = ReaderBookWideLeafViewController(canonicalController: canonical, side: .right)
        let spread = ReaderBookSpreadViewController(leaves: [first, wide])
        spread.view.frame = CGRect(x: 0, y: 0, width: 900, height: 650)
        spread.view.setNeedsLayout()
        spread.view.layoutIfNeeded()
        func hasLighting(_ view: UIView) -> Bool {
            view.layer.sublayers?.contains { $0.name == ReaderBookSpineView.bindingLightingName } == true
        }
        #expect(hasLighting(first.view) && hasLighting(wide.view))
        let unrelated = CALayer()
        first.view.layer.addSublayer(unrelated)
        first.bookBindingEdge = .none
        wide.bookBindingEdge = .none
        #expect(!hasLighting(first.view) && !hasLighting(wide.view))
        #expect(unrelated.superlayer === first.view.layer)
        spread.view.setNeedsLayout()
        spread.view.layoutIfNeeded()
        #expect(hasLighting(first.view) && hasLighting(wide.view))
        spread.releaseLeaves()
        #expect(!hasLighting(first.view) && !hasLighting(wide.view))
    }

    @Test("Canonical next turns the right leaf left for either source order")
    func physicalDirectionPreservesSourceOrder() throws {
        for readingMode in [ReadingMode.ltr, .rtl] {
            let pager = SumiPageCurlViewController(readingMode: readingMode)
            pager.view.frame = CGRect(x: 0, y: 0, width: 900, height: 650)
            let first = ReaderBookSpreadViewController(leaves: [page(.white), page(.systemGray5)])
            let second = ReaderBookSpreadViewController(leaves: [page(.systemGray4), page(.systemGray3)])
            pager.setViewControllers([first], direction: .forward, animated: false)
            pager.view.layoutIfNeeded()
            let next: UIPageViewController.NavigationDirection = readingMode == .rtl ? .reverse : .forward
            pager.setViewControllers([second], direction: next, animated: true)
            let turn = try #require(pager.view.subviews.flatMap(\.subviews).compactMap { $0 as? SumiPageCurlView }.first)
            #expect(turn.rightToLeft)
            #expect(pager.viewControllers?.first === first)
            #expect(first.leaves[0].view.frame.minX == 0)
            #expect(first.leaves[1].view.frame.minX == 450)
            pager.viewWillDisappear(false)
            pager.setViewControllers([second], direction: next == .forward ? .reverse : .forward, animated: true)
            let previous = try #require(pager.view.subviews.flatMap(\.subviews).compactMap { $0 as? SumiPageCurlView }.first)
            #expect(!previous.rightToLeft)
            pager.viewWillDisappear(false)
        }
    }

    @Test("The moving leaf has a separate cast shadow underneath its geometry")
    func castShadowLayerPlacement() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 450, height: 650)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 450, height: 650))
        }
        let turn = SumiPageCurlView(frame: CGRect(x: 0, y: 0, width: 900, height: 650),
                                    oldImages: [image, image], newImages: [image, image], rightToLeft: true)
        let layers = try #require(turn.layer.sublayers)
        let shadowIndex = try #require(layers.firstIndex { $0.name == "sumi.reader.cast-shadow" })
        let paperIndex = try #require(layers.firstIndex { $0.name == "sumi.reader.moving-paper" })
        #expect(shadowIndex < paperIndex)
        turn.update(progress: 0.45)
        let shadow = layers[shadowIndex]
        let firstPath = try #require(shadow.shadowPath)
        #expect(shadow.shadowOpacity > 0.2)
        #expect(shadow.shadowRadius > 5)
        #expect(shadow.contents == nil)
        #expect(firstPath.boundingBoxOfPath.width > 20)
        turn.update(progress: 0.8)
        let secondPath = try #require(shadow.shadowPath)
        #expect(firstPath.boundingBoxOfPath != secondPath.boundingBoxOfPath)
        turn.update(progress: 1)
        #expect(shadow.shadowOpacity < 0.0001)
    }

    @Test("A turn keeps the current controller until its paper has settled")
    func commitsAfterAnimation() async throws {
        let pager = SumiPageCurlViewController(readingMode: .ltr)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 650))
        window.rootViewController = pager
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let first = page(.white)
        let second = page(.systemGray6)
        pager.setViewControllers([first], direction: .forward, animated: false)
        var completed: Bool?
        pager.setViewControllers([second], direction: .forward, animated: true) { completed = $0 }
        #expect(pager.viewControllers?.first === first)
        #expect(completed == nil)
        try await Task.sleep(for: .milliseconds(650))
        #expect(completed == true)
        #expect(pager.viewControllers?.first === second)
        #expect(first.parent == nil)
        #expect(second.parent === pager)
    }

    @Test("Leaving during a turn cancels without advancing or retaining the pending page")
    func cancelledTurn() {
        let pager = SumiPageCurlViewController(readingMode: .rtl)
        pager.view.frame = CGRect(x: 0, y: 0, width: 900, height: 650)
        let first = page(.white)
        let second = page(.systemGray6)
        pager.setViewControllers([first], direction: .forward, animated: false)
        var completed: Bool?
        pager.setViewControllers([second], direction: .reverse, animated: true) { completed = $0 }
        pager.viewWillDisappear(false)
        #expect(completed == false)
        #expect(pager.viewControllers?.first === first)
        #expect(!first.view.isHidden)
        #expect(second.parent == nil)
        // A cancelled display link must not block the next presentation.
        pager.setViewControllers([second], direction: .reverse, animated: false)
        #expect(pager.viewControllers?.first === second)
    }

    @Test("Resizing during a turn cancels the captured mesh without advancing")
    func resizeDuringTurn() {
        let pager = SumiPageCurlViewController(readingMode: .ltr)
        pager.view.frame = CGRect(x: 0, y: 0, width: 900, height: 650)
        let first = page(.white)
        let second = page(.systemGray6)
        pager.setViewControllers([first], direction: .forward, animated: false)
        pager.view.layoutIfNeeded()
        var completed: Bool?
        pager.setViewControllers([second], direction: .forward, animated: true) { completed = $0 }
        pager.view.frame.size = CGSize(width: 650, height: 900)
        pager.view.setNeedsLayout()
        pager.view.layoutIfNeeded()
        #expect(completed == false)
        #expect(pager.viewControllers?.first === first)
        #expect(!first.view.isHidden)
        #expect(second.parent == nil)
    }

    @Test("Changing reading direction recreates the pager with matching accessibility direction")
    func readingDirectionChange() {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var settings = original
        settings["Reader.pagedPageLayout"] = "auto"
        settings["Reader.splitWideImages"] = false
        defaults.setVolatileDomain(settings, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        let temporaryStore = ReaderTemporaryPageStore()
        defer { Task { await temporaryStore.removeAll() } }
        let reader = ReaderPagedViewController(source: nil,
            manga: .init(sourceKey: "sumi-test", key: "direction", title: "Direction"), temporaryPageStore: temporaryStore)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        window.rootViewController = reader
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        reader.readingMode = .ltr
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
        }
        reader.viewModel.pages = (0..<4).map {
            .init(sourceId: "sumi-test", chapterId: "direction", index: $0, image: image)
        }
        reader.loadPageControllers(chapter: .init(key: "direction"))
        reader.loadPages(in: 1...4)
        reader.view.layoutIfNeeded()
        reader.move(toPage: 1, animated: false)
        let first = reader.children.compactMap { $0 as? SumiPageCurlViewController }.first
        #expect(first?.readingMode == .ltr)
        reader.readingMode = .rtl
        let replacement = reader.children.compactMap { $0 as? SumiPageCurlViewController }.first
        #expect(replacement?.readingMode == .rtl)
        #expect(first !== replacement)
        #expect(reader.currentPage == 1)
    }

    @Test("A spread retains independent leaf controllers and equal viewports when resized")
    func spreadLeafOwnership() {
        let first = page(.white)
        let second = page(.systemGray6)
        let spread = ReaderBookSpreadViewController(leaves: [first, second])
        let pager = SumiPageCurlViewController(readingMode: .ltr)
        pager.view.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        pager.setViewControllers([spread], direction: .forward, animated: false)
        pager.view.setNeedsLayout()
        pager.view.layoutIfNeeded()
        #expect(first.parent === spread && second.parent === spread)
        #expect(abs(first.view.frame.width - second.view.frame.width) < 0.001)
        #expect(first.view.frame.maxX == second.view.frame.minX)
        pager.view.frame.size = CGSize(width: 700, height: 500)
        pager.view.setNeedsLayout()
        pager.view.layoutIfNeeded()
        #expect(first.parent === spread && second.parent === spread)
        #expect(abs(first.view.frame.width - 350) < 0.001)
        #expect(abs(second.view.frame.width - 350) < 0.001)
    }
}
