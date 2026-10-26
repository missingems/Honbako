@testable import Aidoku
import AidokuRunner
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct ReaderPageTransitionTests {
    @Test("Center curl uses actual landscape bounds and horizontal reading", arguments: [ReadingMode.ltr, .rtl])
    func transitionPolicy(mode: ReadingMode) {
        let landscape = ReaderPageTransition.resolve(viewport: CGSize(width: 951, height: 669), readingMode: mode, reduceMotion: false)
        #expect(landscape.style == .pageCurl)
        #expect(landscape.orientation == .horizontal)
        #expect(landscape.spine == .mid)
        for size in [CGSize(width: 466, height: 678), CGSize(width: 320, height: 900), .zero, CGSize(width: 800, height: 800)] {
            let policy = ReaderPageTransition.resolve(viewport: size, readingMode: mode, reduceMotion: false)
            #expect(policy.style == .scroll)
            #expect(policy.spine == .none)
        }
        #expect(ReaderPageTransition.resolve(viewport: CGSize(width: 951, height: 669), readingMode: mode, reduceMotion: true).style == .scroll)
        let vertical = ReaderPageTransition.resolve(viewport: CGSize(width: 951, height: 669), readingMode: .vertical, reduceMotion: false)
        #expect(vertical.style == .scroll)
        #expect(vertical.orientation == .vertical)
    }

    @Test("Native center curl accepts two physical leaf controllers and is double sided", arguments: [ReadingMode.ltr, .rtl])
    func nativeCenterContract(mode: ReadingMode) {
        let policy = ReaderPageTransition.resolve(viewport: CGSize(width: 951, height: 669), readingMode: mode, reduceMotion: false)
        let controller = policy.makeController()
        let left = ReaderPageViewController(type: .info(.previous), delegate: nil)
        let right = ReaderPageViewController(type: .info(.next), delegate: nil)
        controller.setViewControllers([left, right], direction: .forward, animated: false)
        controller.loadViewIfNeeded()
        #expect(policy.matches(controller))
        #expect(controller.spineLocation == .mid)
        #expect(controller.viewControllers?.count == 2)
        #expect(controller.viewControllers?.first === left)
        #expect(controller.viewControllers?.last === right)
        #expect(controller.isDoubleSided)
    }

    @Test("Native physical halves display the same canonical page objects and original images", arguments: [ReadingMode.ltr, .rtl])
    func nativeLeavesHaveCanonicalIdentity(mode: ReadingMode) async throws {
        try await withReader(mode: mode, sizing: .fit) { reader, _, window in
            let native = try pager(in: reader)
            let leaves = try normalLeaves(in: native)
            #expect(native.transitionStyle == .pageCurl)
            #expect(native.spineLocation == .mid)
            #expect(native.isDoubleSided)
            let indices = mode == .rtl ? [2, 1] : [1, 2]
            for (leaf, index) in zip(leaves, indices) {
                #expect(leaf === reader.pageViewControllers[index])
                #expect(leaf.pageView?.imageView.image === reader.viewModel.pages[index - 1].image)
                #expect(leaf.zoomView?.zoomView === leaf.pageView)
            }
            try assertHalfBounds(leaves, reader: reader)
            let frames = try renderedFrames(try leaves.map { try #require($0.pageView) }, in: window)
            for (index, frame) in frames.enumerated() {
                let half = leaves[index].view.convert(leaves[index].view.bounds, to: window)
                #expect(frame.width > 10 && frame.height > 10)
                #expect(frame.minX >= half.minX - 0.5)
                #expect(frame.maxX <= half.maxX + 0.5)
                #expect(frame.minY >= half.minY - 0.5)
                #expect(frame.maxY <= half.maxY + 0.5)
            }
            #expect(reader.visibleActualPageRange(in: leaves) == 1...2)
        }
    }

    @Test("Live Reduce Motion changes retain both loaded leaves and their independent reading viewports", arguments: [ReadingMode.ltr, .rtl], [ReaderPageSizing.fit, .fill])
    func styleChangesPreserveLoadedLeaves(mode: ReadingMode, sizing: ReaderPageSizing) async throws {
        var reduceMotion = true
        try await withReader(mode: mode, sizing: sizing, reduceMotion: { reduceMotion }) { reader, _, window in
            let original = try pager(in: reader)
            #expect(original.transitionStyle == .scroll)
            let fallback = try #require(original.viewControllers?.first as? ReaderBookSpreadViewController)
            #expect(fallback.leaves.count == 2)
            let states = try configureIndependentViewports(in: original, window: window, sizing: sizing)
            #expect(states[0].zoom !== states[1].zoom)
            #expect(states[0].offset != states[1].offset)
            for reduced in [false, true, false, true] {
                reduceMotion = reduced
                NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
                try await settle(reader, window: window)
                let replacement = try pager(in: reader)
                #expect(replacement.transitionStyle == (reduced ? .scroll : .pageCurl))
                #expect(replacement.viewControllers?.count == (reduced ? 1 : 2))
                if reduced {
                    #expect(replacement.viewControllers?.first is ReaderBookSpreadViewController)
                } else {
                    #expect(replacement.spineLocation == .mid)
                    #expect(replacement.isDoubleSided)
                }
                try assertLeafStates(states, in: replacement, window: window)
                try assertHalfBounds(try normalLeaves(in: replacement), reader: reader)
                #expect(reader.children.filter { $0 is UIPageViewController }.count == 1)
                #expect(reader.currentPage == 1)
                if !reduced {
                    let taps = replacement.gestureRecognizers.compactMap { $0 as? UITapGestureRecognizer }
                    #expect(taps.allSatisfy { !$0.isEnabled })
                }
            }
        }
    }

    @Test("A cancelled native two-leaf transition commits no progress and releases a deferred style change")
    func cancelledTransitionDefersRebuild() async throws {
        var reduceMotion = false
        try await withReader(mode: .ltr, sizing: .fill, reduceMotion: { reduceMotion }) { reader, delegate, window in
            let original = try pager(in: reader)
            let visible = try #require(original.viewControllers)
            #expect(visible.count == 2)
            let pending = try nextBookGroup(in: reader, mode: .ltr)
            delegate.reports = []
            let page = reader.currentPage
            // Exercise the public delegate state machine. The temporary UI
            // harness separately verifies cancellation using real native touches.
            reader.pageViewController(original, willTransitionTo: pending)
            reduceMotion = true
            NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
            #expect(try pager(in: reader) === original)
            #expect(original.transitionStyle == .pageCurl)
            reader.pageViewController(original, didFinishAnimating: true, previousViewControllers: visible, transitionCompleted: false)
            try await settle(reader, window: window)
            let replacement = try pager(in: reader)
            #expect(replacement !== original)
            #expect(replacement.transitionStyle == .scroll)
            let restored = leaves(in: replacement)
            #expect(restored.count == 2)
            for (a, b) in zip(restored, visible) { #expect(a === b) }
            #expect(reader.currentPage == page)
            #expect(delegate.reports.isEmpty)
        }
    }

    @Test("The latest explicit page selection waits for a pending native curl to cancel")
    func queuedMoveAfterCancelledCurl() async throws {
        try await withReader(mode: .ltr, sizing: .fill) { reader, delegate, window in
            let original = try pager(in: reader)
            let visible = try #require(original.viewControllers)
            let pending = try nextBookGroup(in: reader, mode: .ltr)
            delegate.reports = []
            reader.pageViewController(original, willTransitionTo: pending)
            reader.move(toPage: 3, animated: false)
            reader.move(toPage: 5, animated: false)
            // A slider request cannot reparent the leaf UIKit is still turning.
            #expect(try pager(in: reader) === original)
            #expect(reader.currentPage == 1)
            #expect(reader.visibleActualPageRange(in: leaves(in: original)) == 1...2)
            #expect(delegate.reports.isEmpty)
            reader.pageViewController(original, didFinishAnimating: true, previousViewControllers: visible, transitionCompleted: false)
            try await settle(reader, window: window)
            let final = try pager(in: reader)
            #expect(reader.currentPage == 5)
            #expect(reader.visibleActualPageRange(in: leaves(in: final)) == 5...5)
            #expect(delegate.reports.last == 5...5)
            #expect(!delegate.reports.contains(3...4))
        }
    }

    @Test("The curved binding stays visible and fixed during a native curl and ends cadence on cancellation", arguments: [ReadingMode.ltr, .rtl])
    func bindingPersistsDuringCurl(mode: ReadingMode) async throws {
        try await withReader(mode: mode, sizing: .fill, pageLayout: "auto") { reader, _, window in
            let native = try pager(in: reader)
            let visible = try #require(native.viewControllers)
            let binding = try #require(reader.view.subviews.compactMap { $0 as? ReaderBookSpineView }.first)
            let cadence = try #require(reader.pageTurnCadence)
            #expect(!binding.isHidden)
            #expect(!binding.frame.isEmpty)
            let seam = binding.frame
            let pending = try nextBookGroup(in: reader, mode: mode)
            reader.pageViewController(native, willTransitionTo: pending)
            #expect(!binding.isHidden)
            #expect(binding.frame == seam)
            #if os(iOS) && !targetEnvironment(macCatalyst)
            if #available(iOS 18.0, *) { #expect(cadence.isActive == (window.windowScene != nil)) }
            #endif
            #expect(!cadence.requiresContinuousUpdates)
            reader.view.setNeedsLayout()
            reader.view.layoutIfNeeded()
            #expect(!binding.isHidden)
            #expect(binding.frame == seam)
            #expect(reader.view.subviews.last === binding)
            reader.pageViewController(native, didFinishAnimating: true, previousViewControllers: visible, transitionCompleted: false)
            try await settle(reader, window: window)
            #expect(!binding.isHidden)
            #expect(binding.frame == seam)
            #expect(!cadence.isActive)
            window.frame.size = CGSize(width: 466, height: 678)
            try await settle(reader, window: window)
            #expect(binding.isHidden)
            #expect(!cadence.isActive)
        }
    }

    @Test("A late wide page invalidates native neighbor caches without resetting the current leaves", arguments: [ReadingMode.ltr, .rtl])
    func lateWidePageRebuildsNativeCache(mode: ReadingMode) async throws {
        try await withReader(mode: mode, sizing: .fit) { reader, _, window in
            let original = try pager(in: reader)
            let states = try configureIndependentViewports(in: original, window: window, sizing: .fit)
            let visible = try #require(original.viewControllers)
            for leaf in visible {
                _ = reader.pageViewController(original, viewControllerBefore: leaf)
                _ = reader.pageViewController(original, viewControllerAfter: leaf)
            }
            // Keep the old normal surface a native neighbor query could have
            // cached. It ceases to be a valid slot once its bitmap resolves wide.
            let stalePageThree = reader.bookController(for: .page(3))
            #expect(stalePageThree === reader.pageViewControllers[3])
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let wide = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 400), format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 900, height: 400))
                UIColor.black.setFill()
                context.fill(CGRect(x: 25, y: 25, width: 200, height: 80))
            }
            reader.pageViewControllers[3].clearPage()
            var replacementPage = reader.viewModel.pages[2]
            replacementPage.image = wide
            reader.viewModel.pages[2] = replacementPage
            reader.loadPage(at: 3)
            try await settle(reader, window: window)
            #expect(reader.pageViewControllers[3].isWideImage)
            let plan = try #require(reader.bookPlan)
            #expect(plan.groupIndex(containing: .page(3)) == nil)
            #expect(plan.groupIndex(containing: .wideLeft(3)) != nil)
            #expect(plan.groupIndex(containing: .wideRight(3)) != nil)
            let replacement = try pager(in: reader)
            #expect(replacement !== original)
            #expect(replacement.spineLocation == .mid)
            #expect(replacement.viewControllers?.count == 2)
            #expect(reader.currentPage == 1)
            #expect(reader.visibleActualPageRange(in: leaves(in: replacement)) == 1...2)
            try assertLeafStates(states, in: replacement, window: window)
            #expect(reader.pageViewController(replacement, viewControllerBefore: stalePageThree) == nil)
            #expect(reader.pageViewController(replacement, viewControllerAfter: stalePageThree) == nil)
        }
    }

    @Test("A pending Reduce Motion scroll keeps returning wrappers until native curl can safely replace it")
    func deferredReduceMotionKeepsFallbackDataSourceContract() async throws {
        var reduceMotion = true
        try await withReader(mode: .ltr, sizing: .fit, reduceMotion: { reduceMotion }) { reader, delegate, window in
            let original = try pager(in: reader)
            #expect(original.transitionStyle == .scroll)
            let visible = try #require(original.viewControllers?.first as? ReaderBookSpreadViewController)
            let initialLeaves = visible.leaves
            let pending = try #require(reader.pageViewController(original, viewControllerAfter: visible) as? ReaderBookSpreadViewController)
            #expect(reader.visibleActualPageRange(in: pending.leaves) == 3...4)
            delegate.reports = []
            reader.pageViewController(original, willTransitionTo: [pending])
            reduceMotion = false
            NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
            #expect(try pager(in: reader) === original)
            #expect(original.transitionStyle == .scroll)
            let after = try #require(reader.pageViewController(original, viewControllerAfter: visible) as? ReaderBookSpreadViewController)
            #expect(after.leaves.count == 2)
            #expect(reader.visibleActualPageRange(in: after.leaves) == 3...4)
            let before = try #require(reader.pageViewController(original, viewControllerBefore: pending) as? ReaderBookSpreadViewController)
            #expect(before.leaves.count == 2)
            #expect(reader.visibleActualPageRange(in: before.leaves) == 1...2)
            #expect(delegate.reports.isEmpty)
            reader.pageViewController(original, didFinishAnimating: true, previousViewControllers: [visible], transitionCompleted: false)
            try await settle(reader, window: window)
            let final = try pager(in: reader)
            #expect(final !== original)
            #expect(final.transitionStyle == .pageCurl)
            #expect(final.spineLocation == .mid)
            #expect(final.viewControllers?.count == 2)
            for (leaf, oldLeaf) in zip(leaves(in: final), initialLeaves) { #expect(leaf === oldLeaf) }
            #expect(reader.currentPage == 1)
            #expect(delegate.reports.isEmpty)
        }
    }

    @Test("Folding away and back before a cancelled curl retains both independent reading viewports", arguments: [ReaderPageSizing.fit, .fill])
    func foldBackBeforeCancelRetainsLeaves(sizing: ReaderPageSizing) async throws {
        try await withReader(mode: .rtl, sizing: sizing, pageLayout: "auto") { reader, delegate, window in
            let original = try pager(in: reader)
            let visible = try #require(original.viewControllers)
            let states = try configureIndependentViewports(in: original, window: window, sizing: sizing)
            let pending = try nextBookGroup(in: reader, mode: .rtl)
            delegate.reports = []
            reader.pageViewController(original, willTransitionTo: pending)
            window.frame.size = CGSize(width: 466, height: 678)
            try await settle(reader, window: window)
            #expect(try pager(in: reader) === original)
            window.frame.size = CGSize(width: 951, height: 669)
            try await settle(reader, window: window)
            reader.pageViewController(original, didFinishAnimating: true, previousViewControllers: visible, transitionCompleted: false)
            try await settle(reader, window: window)
            let final = try pager(in: reader)
            #expect(final === original)
            #expect(final.viewControllers?.count == 2)
            try assertLeafStates(states, in: final, window: window)
            #expect(reader.currentPage == 1)
            #expect(delegate.reports.isEmpty)
        }
    }

    @Test("A fold during a pending curl defers rebuilding until cancellation, then restores the same canonical pages")
    func foldDuringCancelThenUnfold() async throws {
        try await withReader(mode: .ltr, sizing: .fill, pageLayout: "auto") { reader, delegate, window in
            let original = try pager(in: reader)
            let visible = try #require(original.viewControllers)
            let first = reader.pageViewControllers[1]
            let image = first.pageView?.imageView.image
            delegate.reports = []
            let pending = try nextBookGroup(in: reader, mode: .ltr)
            reader.pageViewController(original, willTransitionTo: pending)
            window.frame.size = CGSize(width: 466, height: 678)
            try await settle(reader, window: window)
            #expect(try pager(in: reader) === original)
            reader.pageViewController(original, didFinishAnimating: true, previousViewControllers: visible, transitionCompleted: false)
            try await settle(reader, window: window)
            let folded = try pager(in: reader)
            #expect(folded.transitionStyle == .scroll)
            #expect(folded.viewControllers?.count == 1)
            #expect(folded.viewControllers?.first === first)
            #expect(first.pageView?.imageView.image === image)
            #expect(reader.currentPage == 1)
            #expect(delegate.reports.isEmpty)
            window.frame.size = CGSize(width: 951, height: 669)
            try await settle(reader, window: window)
            let opened = try pager(in: reader)
            #expect(opened.transitionStyle == .pageCurl)
            #expect(opened.spineLocation == .mid)
            #expect(opened.viewControllers?.count == 2)
            #expect(leaves(in: opened).contains { $0 === first })
            #expect(first.pageView?.imageView.image === image)
            #expect(reader.currentPage == 1)
        }
    }

    @Test("Visible progress deduplicates wide halves and excludes odd blanks and chapter information", arguments: [ReadingMode.ltr, .rtl])
    func visibleProgress(mode: ReadingMode) async throws {
        try await withReader(mode: mode, sizing: .fit, wideSecondPage: true) { reader, delegate, window in
            for (page, expected) in [(1, 1...1), (2, 2...2), (3, 3...4), (5, 5...5)] {
                delegate.reports = []
                reader.move(toPage: page, animated: false)
                try await settle(reader, window: window)
                let native = try pager(in: reader)
                let visible = leaves(in: native)
                #expect(reader.visibleActualPageRange(in: visible) == expected)
                #expect(delegate.reports.last == expected)
                #expect(native.viewControllers?.count == 2)
                #expect(native.isDoubleSided)
                let plan = try #require(reader.bookPlan)
                let group = try #require(plan.groupIndex(containingCanonicalIndex: page))
                let slots = plan.physicalSlots(in: group, readingMode: mode)
                for (slot, controller) in zip(slots, visible) {
                    #expect(reader.bookController(for: slot) === controller)
                    let after = reader.pageViewController(native, viewControllerAfter: controller)
                    let expectedAfter = plan.adjacentSlot(to: slot, after: true, readingMode: mode).map { reader.bookController(for: $0) }
                    #expect(after === expectedAfter)
                    let before = reader.pageViewController(native, viewControllerBefore: controller)
                    let expectedBefore = plan.adjacentSlot(to: slot, after: false, readingMode: mode).map { reader.bookController(for: $0) }
                    #expect(before === expectedBefore)
                    if slot.canonicalIndex == nil { #expect(reader.visibleActualPageRange(in: controller) == nil) }
                }
            }
            for page in [0, reader.displayPageCount + 1] {
                delegate.reports = []
                reader.move(toPage: page, animated: false)
                try await settle(reader, window: window)
                let visible = leaves(in: try pager(in: reader))
                #expect(visible.count == 2)
                #expect(reader.visibleActualPageRange(in: visible) == nil)
                #expect(delegate.reports.allSatisfy { $0.lowerBound == page && $0.upperBound == page })
            }
        }
    }

    @Test("Wide physical leaves clip the same original bitmap without mutation or duplicate progress", arguments: [ReadingMode.ltr, .rtl])
    func wideLeavesKeepOriginalBitmap(mode: ReadingMode) async throws {
        try await withReader(mode: mode, sizing: .fit, wideSecondPage: true) { reader, delegate, window in
            let canonical = reader.pageViewControllers[2]
            let original = try #require(reader.viewModel.pages[1].image)
            let bytes = original.pngData()
            reader.move(toPage: 2, animated: false)
            try await settle(reader, window: window)
            let native = try pager(in: reader)
            let wide = try leaves(in: native).map { try #require($0 as? ReaderBookWideLeafViewController) }
            #expect(wide.count == 2)
            #expect(wide[0].side == .left)
            #expect(wide[1].side == .right)
            let natural = CGRect(origin: .zero, size: original.size)
            #expect(wide[0].canonicalImageRect.minX == natural.minX)
            #expect(wide[1].canonicalImageRect.maxX == natural.maxX)
            #expect(wide[0].canonicalImageRect.maxX == wide[1].canonicalImageRect.minX)
            #expect(wide[0].canonicalImageRect.union(wide[1].canonicalImageRect) == natural)
            let fullFrames = wide.map { $0.imageView.convert($0.imageView.bounds, to: window) }
            try assertFramesEqual(fullFrames[0], fullFrames[1])
            for leaf in wide {
                #expect(leaf.canonicalController === canonical)
                #expect(leaf.imageView.image === original)
                let content = try #require(leaf.zoomView.zoomView)
                let frame = try #require(leaf.zoomView.pageContentFrame?())
                let drawn = content.convert(frame, to: window)
                let bounds = leaf.view.convert(leaf.view.bounds, to: window)
                #expect(drawn.minX >= bounds.minX - 0.5)
                #expect(drawn.maxX <= bounds.maxX + 0.5)
                #expect(drawn.width > 10 && drawn.height > 10)
                #expect(reader.visibleActualPageRange(in: leaf) == 2...2)
            }
            #expect(reader.visibleActualPageRange(in: wide) == 2...2)
            #expect(delegate.reports.last == 2...2)
            #expect(canonical.pageView?.imageView.image === original)
            #expect(reader.viewModel.pages[1].image === original)
            #expect(original.pngData() == bytes)
            #expect(reader.viewModel.pages.count == 5)
            #expect(reader.displayPageCount == 5)
        }
    }

    @Test("Offset cover pages contain a blank and report only the real page before normal pairing resumes", arguments: [ReadingMode.ltr, .rtl])
    func offsetProgress(mode: ReadingMode) async throws {
        try await withReader(mode: mode, sizing: .fit) { reader, delegate, window in
            reader.toggleOffset()
            try await settle(reader, window: window)
            let native = try pager(in: reader)
            let cover = leaves(in: native)
            #expect(cover.count == 2)
            #expect(reader.visibleActualPageRange(in: cover) == 1...1)
            #expect(delegate.reports.last == 1...1)
            #expect(cover.filter { reader.visibleActualPageRange(in: $0) == nil }.count == 1)
            reader.move(toPage: 2, animated: false)
            try await settle(reader, window: window)
            let paired = leaves(in: try pager(in: reader))
            #expect(paired.count == 2)
            #expect(reader.visibleActualPageRange(in: paired) == 2...3)
            #expect(delegate.reports.last == 2...3)
        }
    }

    @Test("Two separately stored split halves map to one actual progress page")
    func splitHalfProgress() async throws {
        try await withReader(mode: .rtl, sizing: .fit, wideSecondPage: true, splitWideImages: true) { reader, _, _ in
            let halves = (1...reader.displayPageCount).filter { reader.actualPageIndex(from: $0) == 2 }
            #expect(halves.count == 2)
            let controllers = halves.map { reader.pageViewControllers[$0] }
            #expect(reader.visibleActualPageRange(in: controllers) == 2...2)
            for controller in controllers { #expect(reader.visibleActualPageRange(in: controller) == 2...2) }
        }
    }

    @Test("Actual bounds switch between one portrait surface and two landscape surfaces without changing the logical page")
    func liveBoundsPolicy() async throws {
        try await withReader(mode: .rtl, sizing: .fit, pageLayout: "auto") { reader, _, window in
            let current = reader.currentPage
            for size in [CGSize(width: 466, height: 678), CGSize(width: 951, height: 669), CGSize(width: 320, height: 900)] {
                window.frame.size = size
                try await settle(reader, window: window)
                let native = try pager(in: reader)
                let landscape = size.width > size.height
                #expect(native.transitionStyle == (landscape ? .pageCurl : .scroll))
                #expect(native.viewControllers?.count == (landscape ? 2 : 1))
                #expect(native.isDoubleSided == landscape)
                #expect(reader.currentPage == current)
            }
        }
    }

    private struct LeafState {
        let controller: ReaderPageViewController
        let page: ReaderPageView
        let image: UIImage
        let zoom: ZoomableScrollView
        let scale: CGFloat
        let offset: CGPoint
        let frame: CGRect
    }

    private func leaves(in pager: UIPageViewController) -> [UIViewController] {
        if let spread = pager.viewControllers?.first as? ReaderBookSpreadViewController { return spread.leaves }
        return pager.viewControllers ?? []
    }

    private func normalLeaves(in pager: UIPageViewController) throws -> [ReaderPageViewController] {
        let visible = leaves(in: pager)
        #expect(visible.count == 2)
        return try visible.map { try #require($0 as? ReaderPageViewController) }
    }

    private func assertHalfBounds(_ leaves: [ReaderPageViewController], reader: ReaderPagedViewController) throws {
        #expect(leaves.count == 2)
        for (index, leaf) in leaves.enumerated() {
            let bounds = leaf.view.convert(leaf.view.bounds, to: reader.view)
            #expect(abs(bounds.width - reader.view.bounds.width / 2) < 0.5)
            #expect(abs(bounds.minX - CGFloat(index) * reader.view.bounds.width / 2) < 0.5)
            #expect(abs(bounds.minY) < 0.5)
            #expect(abs(bounds.height - reader.view.bounds.height) < 0.5)
        }
    }

    private func configureIndependentViewports(in pager: UIPageViewController, window: UIWindow, sizing: ReaderPageSizing) throws -> [LeafState] {
        try normalLeaves(in: pager).enumerated().map { index, controller in
            let zoom = try #require(controller.zoomView)
            let page = try #require(controller.pageView)
            let image = try #require(page.imageView.image)
            if sizing == .fit { zoom.setZoomScale(index == 0 ? 2.4 : 2.1, animated: false) }
            let minX = -zoom.adjustedContentInset.left
            let maxX = max(minX, zoom.contentSize.width - zoom.bounds.width + zoom.adjustedContentInset.right)
            let minY = -zoom.adjustedContentInset.top
            let maxY = max(minY, zoom.contentSize.height - zoom.bounds.height + zoom.adjustedContentInset.bottom)
            #expect(maxY > minY + 100)
            let fraction: CGFloat = index == 0 ? 0.25 : 0.6
            zoom.setContentOffset(CGPoint(x: minX + (maxX - minX) * fraction, y: minY + (maxY - minY) * fraction), animated: false)
            let frame = try #require(renderedFrames([page], in: window).first)
            return LeafState(controller: controller, page: page, image: image, zoom: zoom, scale: zoom.zoomScale, offset: zoom.contentOffset, frame: frame)
        }
    }

    private func assertLeafStates(_ expected: [LeafState], in pager: UIPageViewController, window: UIWindow) throws {
        let actual = try normalLeaves(in: pager)
        #expect(actual.count == expected.count)
        for (controller, state) in zip(actual, expected) {
            #expect(controller === state.controller)
            #expect(controller.pageView === state.page)
            #expect(state.page.imageView.image === state.image)
            #expect(controller.zoomView === state.zoom)
            #expect(state.page.isDescendant(of: state.zoom))
            #expect(abs(state.zoom.zoomScale - state.scale) < 0.001)
            #expect(abs(state.zoom.contentOffset.x - state.offset.x) < 0.5)
            #expect(abs(state.zoom.contentOffset.y - state.offset.y) < 0.5)
            let frame = try #require(renderedFrames([state.page], in: window).first)
            try assertFramesEqual(frame, state.frame)
        }
    }

    private func assertFramesEqual(_ first: CGRect, _ second: CGRect) throws {
        #expect(abs(first.minX - second.minX) < 0.5)
        #expect(abs(first.minY - second.minY) < 0.5)
        #expect(abs(first.width - second.width) < 0.5)
        #expect(abs(first.height - second.height) < 0.5)
    }

    private func nextBookGroup(in reader: ReaderPagedViewController, mode: ReadingMode) throws -> [UIViewController] {
        let plan = try #require(reader.bookPlan)
        let current = try #require(plan.groupIndex(containingCanonicalIndex: reader.currentPage))
        #expect(current + 1 < plan.groups.count)
        return plan.physicalSlots(in: current + 1, readingMode: mode).map { reader.bookController(for: $0) }
    }

    private func pager(in reader: ReaderPagedViewController) throws -> UIPageViewController {
        try #require(reader.children.compactMap { $0 as? UIPageViewController }.first)
    }

    private func renderedFrames(_ pages: [ReaderPageView], in window: UIWindow) throws -> [CGRect] {
        try pages.map { page in
            let image = try #require(page.imageView.image)
            let frame = ReaderPageSizingGeometry.aspectFitFrame(imageSize: image.size, in: page.imageView.bounds)
            return page.imageView.convert(frame, to: window)
        }
    }

    private func settle(_ reader: ReaderPagedViewController, window: UIWindow) async throws {
        window.setNeedsLayout()
        reader.view.setNeedsLayout()
        window.layoutIfNeeded()
        reader.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 50_000_000)
        window.layoutIfNeeded()
        reader.view.layoutIfNeeded()
    }

    private func withReader(
        mode: ReadingMode,
        sizing: ReaderPageSizing,
        pageLayout: String = "double",
        wideSecondPage: Bool = false,
        splitWideImages: Bool = false,
        reduceMotion: @escaping () -> Bool = { false },
        body: (ReaderPagedViewController, TransitionReaderDelegate, UIWindow) async throws -> Void
    ) async throws {
        let manga = AidokuRunner.Manga(sourceKey: "transition-test", key: "native-book-\(UUID().uuidString)", title: "Book")
        let settings: [String: Any] = [
            "Reader.pagedPageLayout": pageLayout, "Reader.pagesToPreload": 2,
            "Reader.splitWideImages": splitWideImages, "Reader.pagedPageOffset": false,
            "Reader.pagedPageOffset.\(manga.identifier)": false,
            "Reader.animatePageTransitions": false, "Reader.cropBorders": false,
            "Reader.downsampleImages": false, "Reader.upscaleImages": false,
            AppSettings.reader.pageSizing.key: sizing.rawValue
        ]
        var saved: [String: Any] = [:]
        for (key, value) in settings {
            saved[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.set(value, forKey: key)
        }
        defer {
            for key in settings.keys { UserDefaults.standard.set(saved[key], forKey: key) }
            NotificationCenter.default.post(name: .init(AppSettings.reader.pageSizing.key), object: nil)
        }
        let store = ReaderTemporaryPageStore()
        do {
            let chapter = AidokuRunner.Chapter(key: "chapter")
            let delegate = TransitionReaderDelegate()
            let reader = ReaderPagedViewController(source: nil, manga: manga, temporaryPageStore: store, reduceMotionEnabled: reduceMotion)
            reader.delegate = delegate
            reader.readingMode = mode
            reader.loadViewIfNeeded()
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 951, height: 669))
            window.rootViewController = reader
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            reader.chapter = chapter
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let images = (0..<5).map { index -> UIImage in
                let size = wideSecondPage && index == 1 ? CGSize(width: 800, height: 400) : CGSize(width: 200, height: 800)
                return UIGraphicsImageRenderer(size: size, format: format).image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(origin: .zero, size: size))
                    UIColor(hue: CGFloat(index) / 5, saturation: 0.8, brightness: 0.7, alpha: 1).setFill()
                    context.fill(CGRect(x: 20, y: 20, width: 50, height: 50))
                    UIColor.black.setFill()
                    context.fill(CGRect(x: 5 + CGFloat(index) * 9, y: 100, width: 12, height: 200))
                }
            }
            reader.viewModel.pages = images.enumerated().map { index, image in
                Page(sourceId: manga.sourceKey, chapterId: chapter.id, index: index, image: image)
            }
            reader.loadPageControllers(chapter: chapter)
            reader.loadPages(in: 1...reader.displayPageCount)
            try await settle(reader, window: window)
            reader.move(toPage: 1, animated: false)
            try await settle(reader, window: window)
            try await body(reader, delegate, window)
            await store.removeAll()
        } catch {
            await store.removeAll()
            throw error
        }
    }
}

@MainActor
private final class TransitionReaderDelegate: ReaderHoldingDelegate {
    var barsHidden = true
    var reports: [ClosedRange<Int>] = []
    func hideBars() { barsHidden = true }
    func getNextChapter() -> AidokuRunner.Chapter? { nil }
    func getPreviousChapter() -> AidokuRunner.Chapter? { nil }
    func setChapter(_ chapter: AidokuRunner.Chapter) {}
    func setCurrentPage(_ page: Int, position: Double?) { reports.append(page...page) }
    func setCurrentPages(_ pages: ClosedRange<Int>) { reports.append(pages) }
    func setPages(_ pages: [Aidoku.Page]) {}
    func displayPage(_ page: Int) {}
    func setSliderOffset(_ offset: CGFloat) {}
    func setCompleted() {}
}
