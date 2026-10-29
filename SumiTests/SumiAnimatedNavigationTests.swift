@testable import Sumi
import AidokuRunner
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiAnimatedNavigationTests {
    @Test("One and thirteen turns share one eased total timeline without stopping at a binding")
    func constantJourneyTimeline() {
        let duration = SumiPageCurlJourneyTimeline.duration
        for turns in [1, 13] {
            #expect(SumiPageCurlJourneyTimeline.distance(at: 0, turns: turns) == 0)
            #expect(abs(SumiPageCurlJourneyTimeline.distance(at: duration * 0.25, turns: turns)
                        - CGFloat(turns) * 0.15625) < 0.00001)
            #expect(abs(SumiPageCurlJourneyTimeline.distance(at: duration * 0.75, turns: turns)
                        - CGFloat(turns) * 0.84375) < 0.00001)
            #expect(SumiPageCurlJourneyTimeline.distance(at: duration, turns: turns) == CGFloat(turns))
        }
        // The middle of twelve turns is an exact leaf boundary. Route velocity
        // stays continuous there instead of easing to a halt and restarting.
        let delta = 0.0001
        let middle = SumiPageCurlJourneyTimeline.distance(at: duration / 2, turns: 12)
        let before = SumiPageCurlJourneyTimeline.distance(at: duration / 2 - delta, turns: 12)
        let after = SumiPageCurlJourneyTimeline.distance(at: duration / 2 + delta, turns: 12)
        #expect(middle == 6)
        #expect((middle - before) / delta > 20)
        #expect(abs((middle - before) - (after - middle)) < 0.00001)
    }

    @Test("Portrait scrub selections use one native slide regardless of distance")
    func oneAndThirteenTurns() async throws {
        let context = try await makeReader(pageCount: 14)
        defer { context.close() }
        var began: CFTimeInterval = 0
        var durations: [CFTimeInterval] = []
        var beginCount = 0
        context.reader.sumiOnPageTurnBegan = {
            began = CACurrentMediaTime()
            beginCount += 1
        }
        for destination in [2, 14] {
            context.reader.sumiMove(toCanonicalPage: 1)
            context.holding.reports.removeAll()
            #expect(await context.reader.sumiAnimate(toCanonicalPage: destination))
            durations.append(CACurrentMediaTime() - began)
            #expect(context.holding.reports.map(\.lowerBound) == [destination])
            #expect(context.reader.sumiCurrentCanonicalPage == destination)
        }
        #expect(beginCount == 2)
        #expect(durations.allSatisfy { $0 > 0.05 && $0 < 1.5 })
        #expect(abs(durations[0] - durations[1]) < 0.25)
    }

    @Test("Canceling a portrait slide keeps the last committed page")
    func cancelAfterProgress() async throws {
        let context = try await makeReader(pageCount: 14)
        defer { context.close() }
        context.holding.reports.removeAll()
        let journey = Task { await context.reader.sumiAnimate(toCanonicalPage: 14) }
        try await waitForTurn(context)
        let last = context.reader.sumiCurrentCanonicalPage
        context.reader.sumiStopAnimatedNavigation()
        journey.cancel()
        #expect(!(await journey.value))
        #expect(!context.customCurlIsTurning)
        #expect(context.reader.sumiCurrentCanonicalPage == last)
        #expect(context.reader.visibleActualPageRange(in: context.pager.viewControllers ?? []) == last...last)
        #expect(context.holding.reports.isEmpty)
        #expect(context.reader.sumiReadyForOpening)
    }

    @Test("Portrait scrub selections slide directly to the requested page in either direction")
    func adjacentJourney() async throws {
        let context = try await makeReader()
        defer { context.close() }
        context.holding.reports.removeAll()
        #expect(await context.reader.sumiAnimate(toCanonicalPage: 4))
        #expect(context.holding.reports.map(\.lowerBound) == [4])
        #expect(context.reader.sumiCurrentCanonicalPage == 4)
        #expect(context.reader.sumiReadyForOpening)
        context.holding.reports.removeAll()
        #expect(await context.reader.sumiAnimate(toCanonicalPage: 2))
        #expect(context.holding.reports.map(\.lowerBound) == [2])
        #expect(context.reader.sumiCurrentCanonicalPage == 2)
    }

    @Test("Each split half is reachable through the scrubber while history retains its source page")
    func splitHalvesHaveDistinctScrubPositions() async throws {
        let defaults = UserDefaults.standard
        let split = defaults.object(forKey: "Reader.splitWideImages")
        defaults.set(true, forKey: "Reader.splitWideImages")
        defer { defaults.set(split, forKey: "Reader.splitWideImages") }
        for viewport in [CGSize(width: 450, height: 800), CGSize(width: 900, height: 450)] {
            let context = try await makeReader(viewport: viewport, deferredWidePage: 2, pageCount: 4)
            defer { context.close() }
            let reader = context.reader
            try await waitForSplit(reader, total: 5)
            #expect(reader.displayPageCount == 5)
            #expect((1...5).map { reader.actualPageIndex(from: $0) } == [1, 2, 2, 3, 4])
            #expect(reader.sumiScrubberPageCount == 5)
            #expect(reader.sumiScrubberSpreads.flatMap { $0 }.sorted() == [1, 2, 3, 4, 5])
            let first = try #require(reader.sumiPageForScrubber(2))
            let second = try #require(reader.sumiPageForScrubber(3))
            #expect(first.index == 1 && second.index == 1)
            #expect(first.image?.pngData() != second.image?.pngData(),
                    "The two scrub positions must preview their distinct halves rather than the same full source image")
            #expect(await reader.sumiAnimate(toDisplayPage: 2))
            #expect(reader.sumiIsDisplayPageVisible(2))
            #expect(await reader.sumiAnimate(toDisplayPage: 3))
            #expect(reader.sumiIsDisplayPageVisible(3))
            #expect(reader.sumiCurrentCanonicalPage == 2)
            #expect(context.holding.reports.last == 2...2)
            #expect(await reader.sumiAnimate(toDisplayPage: 5))
            #expect(reader.sumiIsDisplayPageVisible(5))
            #expect(reader.sumiCurrentCanonicalPage == 4)
            #expect(await reader.sumiAnimate(toDisplayPage: 3))
            #expect(reader.sumiIsDisplayPageVisible(3))
            #expect(reader.sumiCurrentCanonicalPage == 2)
        }
    }

    @Test("A cancelled portrait move keeps the exact split half, and native swiping can reach its neighbor")
    func splitHalfCancelAndNativeTraversal() async throws {
        let defaults = UserDefaults.standard
        let split = defaults.object(forKey: "Reader.splitWideImages")
        defaults.set(true, forKey: "Reader.splitWideImages")
        defer { defaults.set(split, forKey: "Reader.splitWideImages") }
        let context = try await makeReader(deferredWidePage: 2, pageCount: 4)
        defer { context.close() }
        let reader = context.reader
        try await waitForSplit(reader, total: 5)
        reader.sumiMove(toDisplayPage: 3)
        #expect(reader.sumiIsDisplayPageVisible(3))
        let journey = Task { await reader.sumiAnimate(toDisplayPage: 5) }
        try await waitForTurn(context)
        reader.sumiStopAnimatedNavigation()
        journey.cancel()
        #expect(!(await journey.value))
        #expect(reader.currentPage == 3 && reader.sumiIsDisplayPageVisible(3))
        #expect(reader.sumiCurrentCanonicalPage == 2)
        reader.sumiMove(toDisplayPage: 2)
        let current = try #require(context.pager.viewControllers?.first)
        let next = try #require(reader.pageViewController(context.pager, viewControllerAfter: current))
        #expect(reader.getIndex(of: next) == 3)
        reader.moveLeft()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while reader.currentPage != 3, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(reader.sumiIsDisplayPageVisible(3))
        #expect(reader.sumiCurrentCanonicalPage == 2)
    }

    @Test("Late portrait splitting rebuilds native adjacency without moving the visible print")
    func lateSplitInvalidatesNativeNeighbors() async throws {
        let defaults = UserDefaults.standard
        let split = defaults.object(forKey: "Reader.splitWideImages")
        defaults.set(true, forKey: "Reader.splitWideImages")
        defer { defaults.set(split, forKey: "Reader.splitWideImages") }
        let context = try await makeReader(deferredWidePage: 12, pageCount: 14)
        defer { context.close() }
        let originalPager = context.pager
        #expect(context.reader.displayPageCount == 14)
        context.reader.loadPage(at: 12)
        try await waitForSplit(context.reader, total: 15)
        #expect(context.pager !== originalPager)
        #expect(context.reader.currentPage == 1 && context.reader.sumiIsDisplayPageVisible(1))
        #expect(context.reader.sumiReadyForOpening)
        context.reader.sumiMove(toDisplayPage: 12)
        let current = try #require(context.pager.viewControllers?.first)
        let secondHalf = try #require(context.reader.pageViewController(context.pager, viewControllerAfter: current))
        #expect(context.reader.getIndex(of: secondHalf) == 13)
    }

    @Test("Cold chapter and chapter-selector loads publish native neighbors before any scrub")
    func coldChapterAndSelectorHaveNeighbors() async throws {
        for viewport in [CGSize(width: 450, height: 800), CGSize(width: 900, height: 450)] {
            let context = try await makeReader(viewport: viewport, initiallyEmpty: true)
            defer { context.close() }
            let gate = SumiAnimatedChapterLoadGate()
            defer { gate.finish([]) }
            context.reader.viewModel.sumiPageLoaderOverride = { await gate.load($0) }
            for key in ["cold", "selector"] {
                let chapter = AidokuRunner.Chapter(key: "\(key)-\(UUID())")
                let previousPager = context.pager
                context.reader.setChapter(chapter, startPage: 1)
                try await waitForChapterRequest(gate, chapter: chapter)
                #expect(context.pager === previousPager, "Fetching keeps the old surface until the new graph is ready")
                gate.finish(chapterPages(chapter, count: 6))
                try await waitForChapter(context, chapter: chapter)
                if viewport.width < viewport.height {
                    #expect(context.pager !== previousPager,
                            "A native pager must discard all cached neighbors when its chapter graph changes")
                }
                let current = try #require(context.pager.viewControllers?.first)
                let next = try #require(viewport.width > viewport.height
                    ? context.reader.pageViewController(context.pager, viewControllerBefore: current)
                    : context.reader.pageViewController(context.pager, viewControllerAfter: current))
                let nextIndex = try #require(context.reader.getIndex(of: next))
                #expect(context.reader.pageIndex(from: nextIndex) == (viewport.width > viewport.height ? 3 : 2))
                context.reader.moveLeft()
                try await waitForPage(context, page: viewport.width > viewport.height ? 3 : 2)
            }
        }
    }

    @Test("A reused next-chapter preview loses its cached nil neighbor without a scrub")
    func reusedChapterPreviewHasNativeNeighbor() async throws {
        let context = try await makeReader(pageCount: 6)
        defer { context.close() }
        let first = try #require(context.reader.chapter)
        let second = AidokuRunner.Chapter(key: "boundary-next-\(UUID())")
        let gate = SumiAnimatedChapterLoadGate()
        defer { gate.finish([]) }
        context.reader.viewModel.sumiPageLoaderOverride = { await gate.load($0) }
        context.holding.chapters = [first, second]
        context.holding.selectedChapter = first
        context.reader.refreshChapter(startPage: 1)
        let oldPager = context.pager
        let oldVisible = oldPager.viewControllers ?? []
        let cover = try #require(context.reader.pageViewControllers.last)
        let pages = chapterPages(second, count: 6)
        cover.setPage(pages[0])
        // Reproduce the actual end-of-chapter graph: this visible preview is
        // currently the last controller, so UIKit caches no forward neighbor.
        oldPager.setViewControllers([cover], direction: .forward, animated: false)
        #expect(context.reader.pageViewController(oldPager, viewControllerAfter: cover) == nil)
        context.reader.pageViewController(oldPager, didFinishAnimating: true,
            previousViewControllers: oldVisible, transitionCompleted: true)
        try await waitForChapterRequest(gate, chapter: second)
        gate.finish(pages)
        try await waitForChapter(context, chapter: second)
        #expect(context.pager !== oldPager)
        #expect(context.pager.viewControllers?.first === cover,
                "The prepared chapter cover is retained while its native neighbor cache is replaced")
        let next = try #require(context.reader.pageViewController(context.pager, viewControllerAfter: cover))
        let index = try #require(context.reader.getIndex(of: next))
        #expect(context.reader.pageIndex(from: index) == 2)
        #expect(next === context.reader.pageViewControllers[index])
        context.reader.moveLeft()
        try await waitForPage(context, page: 2)
    }

    @Test("A split discovered during scrub preflight retains the selected source beyond its shifted display position")
    func preparedDestinationSurvivesNewSplit() async throws {
        let defaults = UserDefaults.standard
        let split = defaults.object(forKey: "Reader.splitWideImages")
        defaults.set(true, forKey: "Reader.splitWideImages")
        defer { defaults.set(split, forKey: "Reader.splitWideImages") }
        let context = try await makeReader(viewport: CGSize(width: 900, height: 450), deferredWidePage: 13, pageCount: 14)
        defer { context.close() }
        #expect(context.reader.displayPageCount == 14)
        #expect(await context.reader.sumiPrepareDisplayPage(14))
        #expect(context.reader.displayPageCount == 15)
        #expect(context.reader.actualPageIndex(from: 14) == 13)
        #expect(await context.reader.sumiAnimate(toDisplayPage: 14))
        #expect(context.reader.sumiIsDisplayPageVisible(15))
        #expect(context.reader.sumiCurrentCanonicalPage == 14)
    }

    @Test("A late wide destination cannot consume the first landscape curl as a pager reset")
    func lateWideLandscapeJourney() async throws {
        let defaults = UserDefaults.standard
        let preload = defaults.object(forKey: "Reader.pagesToPreload")
        let split = defaults.object(forKey: "Reader.splitWideImages")
        defaults.set(1, forKey: "Reader.pagesToPreload")
        defaults.set(false, forKey: "Reader.splitWideImages")
        defer {
            defaults.set(preload, forKey: "Reader.pagesToPreload")
            defaults.set(split, forKey: "Reader.splitWideImages")
        }
        let context = try await makeReader(viewport: CGSize(width: 900, height: 450), deferredWidePage: 6)
        defer { context.close() }
        let priorPlan = context.reader.bookPlan
        #expect(await context.reader.sumiPrepareCanonicalPage(6))
        #expect(context.reader.pageViewControllers[6].isWideImage)
        // Distant image discovery has not rebuilt the on-screen grouping yet.
        #expect(context.reader.bookPlan == priorPlan)
        context.holding.reports.removeAll()
        let journey = Task { await context.reader.sumiAnimate(toCanonicalPage: 6) }
        try await waitForTurn(context)
        #expect(context.reader.visibleActualPageRange(in: context.pager.viewControllers ?? []) == 1...2)
        #expect(context.holding.reports.isEmpty)
        #expect(await journey.value)
        #expect(context.holding.reports.map(\.lowerBound) == [3, 5, 6])
        #expect(context.reader.sumiCurrentCanonicalPage == 6)
        #expect(context.reader.sumiScrubberSpreads == [[1, 2], [3, 4], [5], [6]])
        #expect(context.reader.sumiReadyForOpening)
    }

    @Test("Canceling a page journey retains its last fully visible canonical page")
    func cancelJourney() async throws {
        let context = try await makeReader()
        defer { context.close() }
        context.holding.reports.removeAll()
        let task = Task { await context.reader.sumiAnimate(toCanonicalPage: 6) }
        try await waitForTurn(context)
        task.cancel()
        #expect(!(await task.value))
        #expect(!context.customCurlIsTurning)
        #expect(context.reader.sumiCurrentCanonicalPage == 1)
        #expect(context.holding.reports.isEmpty)
        #expect(context.reader.sumiReadyForOpening)
    }

    @Test("A newer selection cancels an old destination instead of queuing a stale jump")
    func supersedingJourney() async throws {
        let context = try await makeReader()
        defer { context.close() }
        context.holding.reports.removeAll()
        let old = Task { await context.reader.sumiAnimate(toCanonicalPage: 6) }
        try await waitForTurn(context)
        #expect(await context.reader.sumiAnimate(toCanonicalPage: 2))
        #expect(!(await old.value))
        #expect(context.reader.sumiCurrentCanonicalPage == 2)
        #expect(context.holding.reports.map(\.lowerBound) == [2])
        #expect(context.reader.sumiReadyForOpening)
    }

    @Test("Portrait has a native sliding surface without curl, spine, or inherited binding shadow")
    func portraitHasNoRestingBindingShadow() async throws {
        let context = try await makeReader()
        defer { context.close() }
        #expect(!(context.pager is SumiPageCurlViewController))
        #expect(context.pager.transitionStyle == .scroll)
        #expect(context.pager.view.accessibilityIdentifier == "sumi.reader.slide")
        let page = try #require(context.pager.viewControllers?.first as? ReaderPageViewController)
        #expect(page.bookBindingEdge == .none)
        let inherited = CALayer()
        inherited.name = ReaderBookSpineView.bindingLightingName
        page.view.layer.addSublayer(inherited)
        page.view.layer.shadowOpacity = 0.4
        page.view.layer.shadowPath = CGPath(rect: page.view.bounds, transform: nil)
        page.updatePaperShape()
        #expect(inherited.superlayer == nil)
        #expect(page.view.layer.shadowOpacity == 0)
        #expect(page.view.layer.shadowPath == nil)
        #expect(!descendants(context.pager.view).contains { ($0 as? ReaderBookSpineView)?.isHidden == false })
        #expect(await context.reader.sumiAnimate(toCanonicalPage: 2))
        #expect(!descendants(context.pager.view).contains { $0 is SumiPageCurlView })
        let settled = try #require(context.pager.viewControllers?.first as? ReaderPageViewController)
        #expect(settled.bookBindingEdge == .none)
        #expect(settled.view.layer.shadowOpacity == 0)
    }

    @Test("Sequential spread leaves stay left to right while next curls right to left")
    func ascendingPhysicalSpreadOrder() async throws {
        let context = try await makeReader(viewport: CGSize(width: 900, height: 450))
        defer { context.close() }
        let spread = try #require(context.pager.viewControllers?.first as? ReaderBookSpreadViewController)
        #expect(spread.leaves[0] === context.reader.pageViewControllers[1])
        #expect(spread.leaves[1] === context.reader.pageViewControllers[2])
        #expect(await context.reader.sumiAnimate(toCanonicalPage: 3))
        let next = try #require(context.pager.viewControllers?.first as? ReaderBookSpreadViewController)
        #expect(next.leaves[0] === context.reader.pageViewControllers[3])
        #expect(next.leaves[1] === context.reader.pageViewControllers[4])
    }

    @Test("Repeated portrait and landscape changes retain the selected leaf and visible artwork")
    func repeatRotation() async throws {
        let context = try await makeReader(viewport: CGSize(width: 900, height: 450))
        defer { context.close() }
        context.reader.sumiMove(toCanonicalPage: 4)
        for size in [CGSize(width: 450, height: 800), CGSize(width: 900, height: 450),
                     CGSize(width: 450, height: 800), CGSize(width: 900, height: 450)] {
            context.reader.view.frame.size = size
            for _ in 0..<3 {
                context.reader.view.setNeedsLayout()
                context.reader.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            let pager = try #require(context.reader.children.compactMap { $0 as? UIPageViewController }.first)
            #expect((pager is SumiPageCurlViewController) == (size.width > size.height))
            let visible = try #require(pager.viewControllers?.first)
            #expect(!visible.view.isHidden)
            #expect(context.reader.sumiCurrentCanonicalPage == 4)
            #expect(context.reader.view.bounds.size == size)
            // Notched phones reserve their top and side cutouts while the
            // Duo canvas uses the full viewport. Rotation must respect both.
            let insets = HonbakoDisplayCanvas.avoidsDisplayCutout(in: context.reader.view)
                ? context.reader.view.safeAreaInsets : .zero
            let paperFrame = CGRect(x: insets.left, y: insets.top,
                width: size.width - insets.left - insets.right, height: size.height - insets.top)
            #expect(pager.view.frame == paperFrame)
            #expect(context.reader.pageViewControllers[4].pageView?.imageView.image != nil)
            if let spread = visible as? ReaderBookSpreadViewController {
                #expect(spread.leaves.allSatisfy { $0.parent === spread && !$0.view.isHidden })
                #expect(spread.leaves[0] === context.reader.pageViewControllers[3])
                #expect(spread.leaves[1] === context.reader.pageViewControllers[4])
            } else {
                #expect(visible === context.reader.pageViewControllers[4])
            }
            // Readiness also includes the asynchronous edge-color sample of
            // any newly sized bitmap. Await that preparation contract after
            // asserting the synchronous remount, rather than assuming a fixed
            // number of layout frames can finish background image work.
            #expect(await context.reader.sumiPrepareCanonicalPage(4))
            #expect(context.reader.sumiReadyForOpening)
        }
    }

    @Test("Leaving a spread clears binding lighting from cached portrait neighbors as well as the selected leaf")
    func portraitNeighborsLoseSpreadLighting() async throws {
        let context = try await makeReader(viewport: CGSize(width: 900, height: 450), pageCount: 8)
        defer { context.close() }
        #expect(await context.reader.sumiAnimate(toCanonicalPage: 3))
        #expect(await context.reader.sumiAnimate(toCanonicalPage: 5))
        #expect(await context.reader.sumiAnimate(toCanonicalPage: 1))
        let cached = context.reader.pageViewControllers[2...6]
        #expect(cached.contains { $0.bookBindingEdge != .none })
        context.reader.view.frame.size = CGSize(width: 450, height: 800)
        for _ in 0..<3 {
            context.reader.view.setNeedsLayout()
            context.reader.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!(context.pager is SumiPageCurlViewController))
        for page in context.reader.pageViewControllers {
            #expect(page.bookBindingEdge == .none)
            #expect(!(page.viewIfLoaded?.layer.sublayers ?? []).contains {
                $0.name == ReaderBookSpineView.bindingLightingName
            })
        }
        let selected = try #require(context.pager.viewControllers?.first)
        let neighbor = try #require(context.reader.pageViewController(context.pager, viewControllerAfter: selected)
            as? ReaderPageViewController)
        #expect(neighbor === context.reader.pageViewControllers[2])
        #expect(neighbor.bookBindingEdge == .none)
        neighbor.view.frame = CGRect(x: 0, y: 0, width: 450, height: 800)
        neighbor.view.setNeedsLayout()
        neighbor.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: neighbor.view.bounds.size, format: format).image { output in
            neighbor.view.layer.render(in: output.cgContext)
        }
        let image = try #require(rendered.cgImage)
        let bitmap = try #require(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try #require(bitmap.data?.assumingMemoryBound(to: UInt8.self))
        func shoulderBrightness(_ x: Int) -> Double {
            let values = (140..<220).map { y in Int(pixels[y * bitmap.bytesPerRow + x * 4]) }
            return Double(values.reduce(0, +)) / Double(values.count)
        }
        #expect(abs(shoulderBrightness(24) - shoulderBrightness(225)) < 5,
                "A cached left shoulder must render as flat paper after the portrait data source reuses it")
        context.reader.view.frame.size = CGSize(width: 900, height: 450)
        for _ in 0..<3 {
            context.reader.view.setNeedsLayout()
            context.reader.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        let spread = try #require(context.pager.viewControllers?.first as? ReaderBookSpreadViewController)
        #expect(spread.leaves.allSatisfy { leaf in
            (leaf.view.layer.sublayers ?? []).contains { $0.name == ReaderBookSpineView.bindingLightingName }
        }, "Returning to landscape restores the binding only on the displayed spread")
    }

    @Test("Rotating during a portrait slide cancels the old viewport and leaves a readable spread")
    func rotateDuringJourney() async throws {
        let context = try await makeReader(pageCount: 14)
        defer { context.close() }
        let journey = Task { await context.reader.sumiAnimate(toCanonicalPage: 14) }
        try await waitForTurn(context)
        let lastComplete = context.reader.sumiCurrentCanonicalPage
        context.reader.view.frame.size = CGSize(width: 900, height: 450)
        for _ in 0..<3 {
            context.reader.view.setNeedsLayout()
            context.reader.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!(await journey.value))
        let pager = try #require(context.reader.children.compactMap { $0 as? SumiPageCurlViewController }.first)
        #expect(!pager.isTurning)
        #expect(context.reader.sumiCurrentCanonicalPage == lastComplete)
        #expect(context.reader.sumiReadyForOpening)
        let spread = try #require(pager.viewControllers?.first as? ReaderBookSpreadViewController)
        #expect(spread.leaves.allSatisfy { $0.parent === spread && !$0.view.isHidden })
        #expect(!descendants(pager.view).contains { $0 is SumiPageCurlView })
        #expect(await context.reader.sumiAnimate(toCanonicalPage: 4))
        #expect(context.reader.sumiCurrentCanonicalPage == 4)
    }

    private func chapterPages(_ chapter: AidokuRunner.Chapter, count: Int) -> [Sumi.Page] {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
        }
        return (0..<count).map { .init(sourceId: "sumi-journey", chapterId: chapter.id, index: $0, image: image) }
    }

    private func waitForChapterRequest(_ gate: SumiAnimatedChapterLoadGate, chapter: AidokuRunner.Chapter) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while gate.requestedChapterID != chapter.id, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(gate.requestedChapterID == chapter.id)
    }

    private func waitForChapter(_ context: SumiAnimatedReaderContext, chapter: AidokuRunner.Chapter) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while (context.reader.viewModel.chapter?.id != chapter.id || !context.reader.sumiReadyForOpening),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(context.reader.viewModel.chapter?.id == chapter.id && context.reader.sumiReadyForOpening)
        #expect(context.reader.sumiCurrentCanonicalPage == 1)
    }

    private func waitForPage(_ context: SumiAnimatedReaderContext, page: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while context.reader.sumiCurrentCanonicalPage != page, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(context.reader.sumiCurrentCanonicalPage == page)
        #expect(context.reader.visibleActualPageRange(in: context.pager.viewControllers ?? [])?.contains(page) == true)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func waitForSplit(_ reader: ReaderPagedViewController, total: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while reader.displayPageCount != total, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(reader.displayPageCount == total)
    }

    private func waitForTurn(_ context: SumiAnimatedReaderContext) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        func started() -> Bool {
            if let curl = context.pager as? SumiPageCurlViewController { return curl.isTurning }
            return context.lifecycle.began
        }
        while !started(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(started())
    }

    private func makeReader(viewport: CGSize = CGSize(width: 450, height: 800),
                            deferredWidePage: Int? = nil, pageCount: Int = 6,
                            initiallyEmpty: Bool = false) async throws -> SumiAnimatedReaderContext {
        let store = ReaderTemporaryPageStore()
        let chapter = AidokuRunner.Chapter(key: "animated-journey-\(UUID())")
        let reader = ReaderPagedViewController(source: nil,
            manga: .init(sourceKey: "sumi-journey", key: "book", title: "Animated pages"),
            temporaryPageStore: store, reduceMotionEnabled: { false })
        let holding = SumiAnimatedNavigationHolding()
        reader.delegate = holding
        reader.readingMode = .rtl
        if !initiallyEmpty {
            reader.chapter = chapter
            reader.viewModel.chapter = chapter
        }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        host.add(child: reader)
        reader.view.frame = CGRect(origin: .zero, size: viewport)
        reader.view.autoresizingMask = []
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
        }
        let wideImage = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 400)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 400, y: 0, width: 400, height: 400))
        }
        if !initiallyEmpty {
            reader.viewModel.pages = (0..<pageCount).map {
                .init(sourceId: "sumi-journey", chapterId: chapter.id, index: $0,
                      image: $0 + 1 == deferredWidePage ? wideImage : image)
            }
            reader.loadPageControllers(chapter: chapter)
            reader.loadPages(in: 1...(deferredWidePage == nil ? pageCount : 2))
            reader.sumiMove(toCanonicalPage: 1)
            for _ in 0..<5 {
                window.layoutIfNeeded(); reader.view.setNeedsLayout(); reader.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(25))
            }
            let readyDeadline = ContinuousClock.now.advanced(by: .seconds(3))
            while !reader.sumiReadyForOpening, ContinuousClock.now < readyDeadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(reader.sumiReadyForOpening)
        }
        let pager = try #require(reader.children.compactMap { $0 as? UIPageViewController }.first)
        let lifecycle = SumiAnimatedNavigationLifecycle()
        reader.sumiOnPageTurnBegan = { lifecycle.began = true }
        return SumiAnimatedReaderContext(reader: reader, initialPager: pager, window: window, store: store, holding: holding, lifecycle: lifecycle)
    }
}

@MainActor
private struct SumiAnimatedReaderContext {
    let reader: ReaderPagedViewController
    let initialPager: UIPageViewController
    var pager: UIPageViewController {
        reader.children.compactMap { $0 as? UIPageViewController }.first ?? initialPager
    }
    let window: UIWindow
    let store: ReaderTemporaryPageStore
    let holding: SumiAnimatedNavigationHolding
    let lifecycle: SumiAnimatedNavigationLifecycle
    var customCurlIsTurning: Bool { (pager as? SumiPageCurlViewController)?.isTurning == true }
    func close() {
        window.isHidden = true
        window.rootViewController = nil
        Task { await store.removeAll() }
    }
}

@MainActor
private final class SumiAnimatedNavigationLifecycle {
    var began = false
}

@MainActor
private final class SumiAnimatedChapterLoadGate {
    private(set) var requestedChapterID: String?
    private var continuation: CheckedContinuation<[Sumi.Page], Never>?

    func load(_ chapter: AidokuRunner.Chapter) async -> [Sumi.Page] {
        await withCheckedContinuation { continuation in
            requestedChapterID = chapter.id
            self.continuation = continuation
        }
    }

    func finish(_ pages: [Sumi.Page]) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: pages)
    }
}

@MainActor
private final class SumiAnimatedNavigationHolding: ReaderHoldingDelegate {
    var barsHidden = true
    var reports: [ClosedRange<Int>] = []
    var chapters: [AidokuRunner.Chapter] = []
    var selectedChapter: AidokuRunner.Chapter?
    func hideBars() { barsHidden = true }
    func getNextChapter() -> AidokuRunner.Chapter? {
        guard let selectedChapter, let index = chapters.firstIndex(of: selectedChapter) else { return nil }
        return chapters[safe: index + 1]
    }
    func getPreviousChapter() -> AidokuRunner.Chapter? {
        guard let selectedChapter, let index = chapters.firstIndex(of: selectedChapter) else { return nil }
        return chapters[safe: index - 1]
    }
    func setChapter(_ chapter: AidokuRunner.Chapter) { selectedChapter = chapter }
    func setCurrentPage(_ page: Int, position: Double?) { reports.append(page...page) }
    func setCurrentPages(_ pages: ClosedRange<Int>) { reports.append(pages) }
    func setPages(_ pages: [Sumi.Page]) {}
    func displayPage(_ page: Int) {}
    func setSliderOffset(_ offset: CGFloat) {}
    func setCompleted() {}
}
