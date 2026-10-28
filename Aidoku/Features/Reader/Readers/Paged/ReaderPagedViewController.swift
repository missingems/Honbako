//
//  ReaderPagedViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import AidokuRunner
import UIKit
import VisionKit

class ReaderPagedViewController: BaseObservingViewController {

    let viewModel: ReaderPagedViewModel

    weak var delegate: ReaderHoldingDelegate?

    var chapter: AidokuRunner.Chapter? {
        didSet {
            #if SUMI
            if oldValue?.id != chapter?.id { sumiCancelAnimatedNavigation() }
            #endif
        }
    }
    var readingMode: ReadingMode = .rtl {
        didSet(oldValue) {
            guard readingMode != oldValue else { return }
            #if SUMI
            sumiCancelAnimatedNavigation()
            #endif
            updatePageTransitionIfNeeded()
            #if SUMI
            refreshChapter(startPage: firstDisplayPage(forActual: sumiCurrentCanonicalPage))
            #else
            refreshChapter(startPage: currentPage)
            #endif
        }
    }
    var pageViewControllers: [ReaderPageViewController] = []
    var currentPage = 0

    private var usesDoublePages = false
    private var usesAutoPageLayout = false
    private var pageOffsetEnabled = false

    private var pageOffsetKey: String {
        "Reader.pagedPageOffset.\(viewModel.manga.identifier)"
    }

    private var splitWideImages = UserDefaults.standard.bool(forKey: "Reader.splitWideImages")
    private var isolatedPages: Set<Int> = []
    private var manuallyIsolatedPages: Set<Int> = []
    #if SUMI
    private var pagesToPreload = SumiPagePreloadWindow.ahead
    #else
    private lazy var pagesToPreload = UserDefaults.standard.integer(forKey: "Reader.pagesToPreload")
    #endif
    #if SUMI
    private let pagePrefetcher = ReaderPagePrefetcher(decodedImages: true)
    private var sumiPreparedNextChapterID: String?
    private var sumiNextChapterRetryAfter = Date.distantPast
    #else
    private let pagePrefetcher = ReaderPagePrefetcher()
    #endif
    private var nextChapterPreloadTask: Task<Void, Never>?

    // Split pages tracking
    private var actualPageIndices: [Int] = []
    private var splitPages: [Int: [Page]] = [:]
    private var previousPreviewSplitPages: [Page]?
    private var nextPreviewSplitPages: [Page]?

    private var isTransitioning = false {
        didSet { updatePageTurnCadence() }
    }
    private(set) var pageTurnCadence: ReaderPageTurnCadence?
    private var transitionPagerFrame: CGRect?
    private var programmaticMove = false
    private var pendingSpreadRebuild = false
    private var pendingPageMove: (page: Int, animated: Bool, resetGesture: Bool, chapterID: String?)?
    private var pendingPageTransitionRebuild = false
    private var pageGraphNeedsPagerReset = false
    private var isRebuildingPageViewController = false
    private let reduceMotionEnabled: () -> Bool
    private(set) var bookPlan: ReaderBookPlan?
    private var bookCanonicalControllers: [ReaderPageViewController] = []
    private var bookControllers: [ReaderBookPlan.Slot: UIViewController] = [:]
    private var bookSpreads: [Int: ReaderBookSpreadViewController] = [:]
    private var displayingBookLayout = false
    private var bookPlanNeedsPagerReset = false
    /// Physical spread order is independent of the direction used to ask the
    /// source for its next page. Sumi lays sequential pages left to right.
    private var bookLeafOrder: ReadingMode {
        #if SUMI
        .ltr
        #else
        readingMode
        #endif
    }
    private let bookSpineView = ReaderBookSpineView()
#if SUMI
    private var sumiAnimationGeneration = UUID()
    private var sumiLastLayoutSize: CGSize = .zero
    private var sumiChapterStateView: SumiChapterBoundaryView?

    private func sumiChapterState() -> SumiChapterBoundaryView {
        if let sumiChapterStateView { return sumiChapterStateView }
        let state = SumiChapterBoundaryView(frame: view.bounds)
        state.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(state)
        node.accessibilityElements = [state]
        sumiChapterStateView = state
        return state
    }

    private func sumiHideChapterState() {
        sumiChapterStateView?.removeFromSuperview()
        sumiChapterStateView = nil
        node.accessibilityElements = nil
        view.setNeedsLayout()
    }
    private var sumiIsAdaptingViewport = false
    private var sumiAnimationViewport: CGSize?
    private var sumiAnimationStepOwner: UUID?
    private var sumiAnimationPreviousFocus: (chapterID: String, page: Int)?
    private struct SumiSlideNavigation {
        let originalDisplayPage: Int
        let destinationPage: Int
        let completion: (Bool) -> Void
    }
    private var sumiSlideNavigation: SumiSlideNavigation?
    private weak var sumiSlidePan: UIPanGestureRecognizer?
    private var sumiSlidePanStarted = false
    private let sumiPaperHaptics = SumiPaperHaptics(inputMode: "portraitSwipe")
    private var sumiSequenceIsActive = false
    private var sumiCanonicalFocus: (chapterID: String, page: Int)?
    private var sumiQueuedCanonicalFocus: (chapterID: String, page: Int)?
    private var sumiPreparedScrubberTarget: (chapterID: String, display: Int, source: Int, offset: Int)?
    var sumiCurrentCanonicalPage: Int {
        if let focus = sumiCanonicalFocus, focus.chapterID == chapter?.id { return focus.page }
        return actualPageIndex(from: currentPage)
    }

    var sumiPageSizingOverride: ReaderPageSizing? {
        didSet {
            guard oldValue != sumiPageSizingOverride, isViewLoaded else { return }
            applySumiPageSizing()
            view.setNeedsLayout()
        }
    }
    var sumiEffectivePageSizing: ReaderPageSizing { sumiPresentation.pageSizing }
    var sumiUsesSpreads: Bool { sumiPresentation.usesDoublePages }
    var sumiOnPageInteraction: (() -> Void)?
    var sumiOnPageTurnBegan: (() -> Void)?
    private let sumiPriorityGestures = NSHashTable<UIGestureRecognizer>.weakObjects()
    func sumiGivePriority(to edgeSwipe: UIGestureRecognizer) {
        func prioritize(_ gesture: UIGestureRecognizer) {
            guard gesture !== edgeSwipe, !sumiPriorityGestures.contains(gesture) else { return }
            gesture.require(toFail: edgeSwipe)
            gesture.addTarget(self, action: #selector(sumiPageInteraction(_:)))
            sumiPriorityGestures.add(gesture)
        }
        func visit(_ view: UIView) {
            if let scroll = view as? UIScrollView { prioritize(scroll.panGestureRecognizer) }
            view.subviews.forEach(visit)
        }
        pageViewController.gestureRecognizers.forEach(prioritize)
        visit(pageViewController.view)
    }
    @objc private func sumiPageInteraction(_ gesture: UIGestureRecognizer) {
        if gesture.state == .began { sumiOnPageInteraction?() }
    }
    var sumiScrubberSpreads: [[Int]] {
        guard usesBookLayout, let bookPlan else { return actualPageIndices.indices.map { [$0 + 1] } }
        return bookPlan.groups.compactMap { slots in
            let indices = slots.compactMap(\.canonicalIndex).filter { index in
                guard pageViewControllers.indices.contains(index), case .page = pageViewControllers[index].type else { return false }
                return true
            }
            let pages = Array(Set(indices.map { pageIndex(from: $0) }))
                .filter { $0 > 0 && $0 <= displayPageCount }.sorted()
            return pages.isEmpty ? nil : pages
        }
    }

    var sumiScrubberPageCount: Int { displayPageCount }
    var sumiScrubberCurrentPage: Int { min(max(1, currentPage), max(1, displayPageCount)) }

    /// Split leaves have separate scrub positions and artwork, while reading
    /// history continues to use their shared source page number.
    func sumiPageForScrubber(_ displayPage: Int) -> Page? {
        guard (1...max(1, displayPageCount)).contains(displayPage), displayPageCount > 0 else { return nil }
        let actual = actualPageIndex(from: displayPage)
        if let leaves = splitPages[actual] {
            return leaves[safe: splitIndex(for: displayPage, actualPageIndex: actual)]
        }
        return viewModel.pages[safe: actual - 1]
    }

    func sumiIsDisplayPageVisible(_ displayPage: Int) -> Bool {
        canonicalControllers(in: pageViewController.viewControllers ?? []).contains { page in
            guard case .page = page.type, let index = pageViewControllers.firstIndex(of: page) else { return false }
            return pageIndex(from: index) == displayPage
        }
    }

    func sumiMove(toDisplayPage displayPage: Int) {
        guard displayPage > 0, displayPage <= displayPageCount else { return }
        sumiCancelAnimatedNavigation()
        guard let chapter else { return }
        let canonical = actualPageIndex(from: displayPage)
        if isTransitioning { sumiQueuedCanonicalFocus = (chapter.id, canonical) }
        else { sumiCanonicalFocus = (chapter.id, canonical); sumiQueuedCanonicalFocus = nil }
        move(toPage: displayPage, animated: false)
        pageViewController.view.setNeedsLayout()
        pageViewController.view.layoutIfNeeded()
    }

    func sumiPrepareDisplayPage(_ displayPage: Int) async -> Bool {
        sumiPreparedScrubberTarget = nil
        guard displayPage > 0, displayPage <= displayPageCount, let chapterID = chapter?.id else { return false }
        let source = actualPageIndex(from: displayPage)
        let offset = splitIndex(for: displayPage, actualPageIndex: source)
        let generation = sumiAnimationGeneration
        guard await sumiPrepareCanonicalPage(source), !Task.isCancelled,
              chapter?.id == chapterID, sumiAnimationGeneration == generation else { return false }
        // Preflight can discover another split before this destination. Keep
        // the source/half identity rather than reinterpreting its old ordinal.
        sumiPreparedScrubberTarget = (chapterID, displayPage, source, offset)
        return true
    }

    func sumiAnimate(toDisplayPage displayPage: Int) async -> Bool {
        if let target = sumiPreparedScrubberTarget,
           target.chapterID == chapter?.id, target.display == displayPage {
            sumiPreparedScrubberTarget = nil
            return await sumiAnimate(toSourcePage: target.source, splitOffset: target.offset)
        }
        guard displayPage > 0, displayPage <= displayPageCount else { return false }
        let canonical = actualPageIndex(from: displayPage)
        let offset = splitIndex(for: displayPage, actualPageIndex: canonical)
        return await sumiAnimate(toSourcePage: canonical, splitOffset: offset)
    }

    func sumiSetPageSizing(_ sizing: ReaderPageSizing) {
        sumiPageSizingOverride = sizing
        guard isViewLoaded, !isTransitioning else { return }
        // Legacy sizing requests can refresh the layout, but Sumi's
        // presentation policy always keeps the complete page fitted.
        for controller in leafControllers(in: pageViewController.viewControllers ?? []) {
            zoomView(in: controller)?.updatePageSizing(resetZoom: true)
        }
    }

    /// Sidebar and scrubber positions use source page numbers, before any wide
    /// image is split into multiple display leaves.
    func sumiMove(toCanonicalPage page: Int) {
        sumiCancelAnimatedNavigation()
        guard let chapter, !viewModel.pages.isEmpty else { return }
        let canonicalPage = min(max(page, 1), viewModel.pages.count)
        if isTransitioning {
            sumiQueuedCanonicalFocus = (chapter.id, canonicalPage)
        } else {
            sumiCanonicalFocus = (chapter.id, canonicalPage)
            sumiQueuedCanonicalFocus = nil
        }
        move(toPage: firstDisplayPage(forActual: canonicalPage), animated: false)
        pageViewController.view.setNeedsLayout()
        pageViewController.view.layoutIfNeeded()
    }

    /// Use a native slide in portrait and a paper journey in landscape.
    /// Preflight warms artwork; progress changes only after a visible handoff.
    func sumiAnimate(toCanonicalPage requestedPage: Int) async -> Bool {
        await sumiAnimate(toSourcePage: requestedPage, splitOffset: 0)
    }

    private func sumiAnimate(toSourcePage requestedPage: Int, splitOffset: Int) async -> Bool {
        sumiCancelAnimatedNavigation()
        guard let chapterID = chapter?.id, viewModel.chapter?.id == chapterID,
              isViewLoaded, !viewModel.pages.isEmpty, (1...viewModel.pages.count).contains(requestedPage) else { return false }
        let generation = sumiAnimationGeneration
        let mode = readingMode
        let customCurl = sumiPresentation.usesCustomCurl
        let viewport = view.bounds.size
        guard viewport.width > 1, viewport.height > 1 else { return false }
        sumiAnimationViewport = viewport
        defer {
            sumiCancelOwnedAnimation(generation)
            if sumiAnimationGeneration == generation { sumiAnimationViewport = nil }
        }
        @MainActor func remainsCurrent() -> Bool {
            !Task.isCancelled && self.sumiAnimationGeneration == generation
                && self.chapter?.id == chapterID && self.viewModel.chapter?.id == chapterID
                && self.view.bounds.size == viewport && self.readingMode == mode
                && self.sumiPresentation.usesCustomCurl == customCurl
        }
        func destinationDisplayPage() -> Int {
            min(firstDisplayPage(forActual: requestedPage) + splitOffset, lastDisplayPage(forActual: requestedPage))
        }
        if !customCurl {
            guard await sumiPrepareCanonicalPage(requestedPage, whileCurrent: remainsCurrent), remainsCurrent() else { return false }
            if destinationDisplayPage() == currentPage { return sumiReadyForOpening }
            let completed = await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    guard remainsCurrent() else { continuation.resume(returning: false); return }
                    sumiAnimationPreviousFocus = sumiCanonicalFocus
                    sumiAnimationStepOwner = generation
                    sumiSlideNavigation = SumiSlideNavigation(
                        originalDisplayPage: currentPage, destinationPage: requestedPage,
                        completion: { continuation.resume(returning: $0) })
                    sumiOnPageTurnBegan?()
                    move(toPage: destinationDisplayPage(), animated: !reduceMotionEnabled()) { [weak self] result in
                        guard let self, self.sumiAnimationStepOwner == generation,
                              let navigation = self.sumiSlideNavigation else { return }
                        self.sumiSlideNavigation = nil
                        self.sumiAnimationStepOwner = nil
                        self.sumiAnimationPreviousFocus = nil
                        navigation.completion(result)
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in self?.sumiCancelOwnedAnimation(generation) }
            }
            return completed && remainsCurrent() && sumiReadyForOpening && sumiIsDisplayPageVisible(destinationDisplayPage())
        }
        let initialDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while isTransitioning {
            guard remainsCurrent(), ContinuousClock.now < initialDeadline else { return false }
            do { try await Task.sleep(for: .milliseconds(12)) } catch { return false }
        }
        // Resolve all artwork before starting one fixed-duration animation.
        // Loading a distant wide original can change every following spread.
        let startingPage = sumiCurrentCanonicalPage
        let direction = requestedPage >= startingPage ? 1 : -1
        let pagesToPrepare = Array(stride(from: startingPage, through: requestedPage, by: direction))
        guard await sumiPrepareCanonicalPages(pagesToPrepare, whileCurrent: remainsCurrent),
              remainsCurrent(), sumiReconcileNavigationBookPlan() else { return false }
        let groups = sumiScrubberSpreads
        guard let currentGroup = groups.firstIndex(where: { $0.contains(currentPage) }),
              let destinationGroup = groups.firstIndex(where: { $0.contains(destinationDisplayPage()) }) else { return false }
        if currentGroup == destinationGroup {
            if sumiCurrentCanonicalPage != requestedPage || currentPage != destinationDisplayPage() {
                sumiCanonicalFocus = (chapterID, requestedPage)
                move(toPage: destinationDisplayPage(), animated: false)
            }
            return remainsCurrent() && sumiReadyForOpening
        }
        let groupStep = destinationGroup > currentGroup ? 1 : -1
        let route = stride(from: currentGroup + groupStep, through: destinationGroup, by: groupStep)
        var canonicalPages: [Int] = []
        var steps: [SumiPageCurlViewController.JourneyStep] = []
        var previousDisplay = currentPage
        for group in route {
            guard let first = groups[group].first else { return false }
            let display = group == destinationGroup ? destinationDisplayPage() : first
            let canonicalPage = actualPageIndex(from: display)
            let controllers = presentationControllers(for: display, transition: desiredTransition)
            guard !controllers.isEmpty, !usesBookLayout || !bookPlanNeedsPagerReset else { return false }
            let forward = readingMode == .rtl ? previousDisplay > display : previousDisplay < display
            steps.append(.init(controllers: controllers, direction: forward ? .forward : .reverse))
            canonicalPages.append(canonicalPage)
            previousDisplay = display
        }
        let itinerary = steps
        let itineraryPages = canonicalPages
        guard remainsCurrent(), let pager = pageViewController as? SumiPageCurlViewController else { return false }
        sumiAnimationPreviousFocus = sumiCanonicalFocus
        sumiAnimationStepOwner = generation
        sumiSequenceIsActive = true
        isTransitioning = true
        programmaticMove = true
        freezePagerViewport()
        let completed = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                guard remainsCurrent() else { continuation.resume(returning: false); return }
                pager.animateJourney(through: itinerary, began: { [weak self] in
                    self?.sumiOnPageTurnBegan?()
                }, didCompleteStep: { [weak self] index, previous in
                    guard let self, remainsCurrent(), self.sumiAnimationStepOwner == generation else { return }
                    let page = itineraryPages[index]
                    self.sumiCanonicalFocus = (chapterID, page)
                    self.sumiAnimationPreviousFocus = self.sumiCanonicalFocus
                    self.programmaticMove = true
                    self.pageViewController(pager, didFinishAnimating: true,
                                            previousViewControllers: previous, transitionCompleted: true)
                }, completion: { [weak self] result in
                    if let self, self.sumiAnimationStepOwner == generation {
                        self.sumiSequenceIsActive = false
                        self.pageViewController(pager, didFinishAnimating: true,
                                                previousViewControllers: [], transitionCompleted: false)
                    }
                    continuation.resume(returning: result)
                })
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.sumiCancelOwnedAnimation(generation) }
        }
        guard completed, remainsCurrent(), sumiReadyForOpening,
              sumiIsDisplayPageVisible(destinationDisplayPage()) else { return false }
        sumiAnimationStepOwner = nil
        sumiAnimationPreviousFocus = nil
        sumiPreloadNeighborhood(around: currentPage, discardDistantPages: true)
        return true
    }

    /// Image preflight may discover a wide page beyond the live prefetch range.
    /// Reconcile its plan at the current position before an adjacent turn: a
    /// deferred pager reset must never consume that turn as an instant jump.
    private func sumiReconcileNavigationBookPlan() -> Bool {
        guard !isTransitioning else { return false }
        guard usesBookLayout else { return true }
        let selectedPage = sumiCurrentCanonicalPage
        let selectedDisplay = currentPage
        let transition = desiredTransition
        prepareBookPlan()
        guard bookPlanNeedsPagerReset else { return true }
        if pagerMatches(transition), displayingBookLayout, visiblePresentationMatchesCurrentLayout() {
            // The custom pager has no cached offscreen leaves. A distant plan
            // change can keep this exact visible wrapper and its textures.
            bookPlanNeedsPagerReset = false
        } else {
            let current = presentationControllers(for: selectedDisplay, transition: transition)
            guard !current.isEmpty else { return false }
            replacePager(with: transition, displaying: current)
        }
        return visibleActualPageRange(in: pageViewController.viewControllers ?? [])?.contains(selectedPage) == true
    }

    private func sumiCancelOwnedAnimation(_ generation: UUID) {
        guard sumiAnimationStepOwner == generation else { return }
        if let navigation = sumiSlideNavigation {
            sumiSlideNavigation = nil
            sumiAnimationStepOwner = nil
            sumiCanonicalFocus = sumiAnimationPreviousFocus
            sumiAnimationPreviousFocus = nil
            isTransitioning = false
            programmaticMove = false
            // Discard the in-flight native pager so its delayed completion can
            // never commit an obsolete selection or interfere with a new slide.
            let controllers = presentationControllers(for: navigation.originalDisplayPage, transition: desiredTransition)
            replacePager(with: desiredTransition, displaying: controllers)
            settlePagerViewport()
            navigation.completion(false)
            return
        }
        let pager = pageViewController as? SumiPageCurlViewController
        let currentRange = visibleActualPageRange(in: pageViewController.viewControllers ?? [])
        if pager?.isTurning == true || sumiCanonicalFocus.map({ currentRange?.contains($0.page) != true }) == true {
            sumiCanonicalFocus = sumiAnimationPreviousFocus
        }
        let wasSequence = sumiSequenceIsActive
        sumiSequenceIsActive = false
        sumiAnimationStepOwner = nil
        sumiAnimationPreviousFocus = nil
        pager?.cancelCurrentTurn()
        if wasSequence {
            pageViewController(pageViewController, didFinishAnimating: true,
                               previousViewControllers: [], transitionCompleted: false)
        }
    }

    /// Closing persists only the last complete paper surface. Stop an owned
    /// curl synchronously before a caller starts saving reading progress.
    func sumiStopAnimatedNavigation() {
        let interruptedNativeTurn = !(pageViewController is SumiPageCurlViewController)
            && isTransitioning && !programmaticMove && sumiAnimationStepOwner == nil
        let settledDisplayPage = currentPage
        sumiCancelAnimatedNavigation()
        (pageViewController as? SumiPageCurlViewController)?.cancelCurrentTurn()
        if interruptedNativeTurn {
            // A second touch may interrupt a native one-finger slide. Dispose
            // of that pager synchronously before the book captures its paper;
            // its delayed completion cannot change the saved reading position.
            pendingPageMove = nil
            sumiQueuedCanonicalFocus = nil
            isTransitioning = false
            let controllers = presentationControllers(for: settledDisplayPage, transition: desiredTransition)
            if !controllers.isEmpty {
                replacePager(with: desiredTransition, displaying: controllers)
                settlePagerViewport()
            }
        }
    }

    private func sumiCancelAnimatedNavigation() {
        sumiPreparedScrubberTarget = nil
        let previousGeneration = sumiAnimationGeneration
        sumiAnimationGeneration = UUID()
        sumiAnimationViewport = nil
        sumiCancelOwnedAnimation(previousGeneration)
    }

    /// Warm the entire destination spread without moving or reporting progress.
    /// Image discovery can change pairing, so resolve the group again while loading.
    func sumiPrepareCanonicalPage(_ page: Int, whileCurrent: (@MainActor () -> Bool)? = nil) async -> Bool {
        await sumiPrepareCanonicalPages([page], whileCurrent: whileCurrent)
    }

    /// Start the route's requests together, then wait for one stable grouping.
    /// Cached artwork therefore incurs one preparation pass, not one delay per leaf.
    private func sumiPrepareCanonicalPages(_ pages: [Int], whileCurrent: (@MainActor () -> Bool)?) async -> Bool {
        guard whileCurrent?() != false, let chapterID = chapter?.id, viewModel.chapter?.id == chapterID,
              !viewModel.pages.isEmpty, !pages.isEmpty, pages.allSatisfy({ (1...viewModel.pages.count).contains($0) }), isViewLoaded else { return false }
        let viewport = view.bounds.size
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        func groups() -> [[Int]] {
            let plan = usesBookLayout ? makeBookPlan() : nil
            return pages.map { sumiPreparationIndices(for: $0, plan: plan) }
        }
        while ContinuousClock.now < deadline {
            guard !Task.isCancelled, whileCurrent?() != false, chapter?.id == chapterID, viewModel.chapter?.id == chapterID,
                  view.bounds.size == viewport else { return false }
            guard !isTransitioning else {
                try? await Task.sleep(for: .milliseconds(20))
                continue
            }
            let preparedGroups = groups()
            let indices = Array(Set(preparedGroups.flatMap { $0 })).sorted()
            guard !indices.isEmpty else { return false }
            for index in indices {
                guard pageViewControllers.indices.contains(index), case .page = pageViewControllers[index].type else { continue }
                loadPage(at: pageIndex(from: index))
            }
            if sumiPreparationImagesReady(indices) {
                // Let image-size callbacks finish regrouping before handing off.
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled, whileCurrent?() != false, chapter?.id == chapterID, viewModel.chapter?.id == chapterID,
                      view.bounds.size == viewport else { return false }
                if preparedGroups == groups(), sumiPreparationImagesReady(indices) { return true }
            } else {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        return false
    }

    private func sumiPreparationImagesReady(_ indices: [Int]) -> Bool {
        !indices.isEmpty && indices.allSatisfy { index in
            guard pageViewControllers.indices.contains(index), case .page = pageViewControllers[index].type else { return false }
            return pageViewControllers[index].pageView?.sumiIsImageReady == true
        }
    }

    private func sumiPreparationIndices(for page: Int, plan preparedPlan: ReaderBookPlan? = nil) -> [Int] {
        let displays = firstDisplayPage(forActual: page)...lastDisplayPage(forActual: page)
        if usesBookLayout {
            let plan = preparedPlan ?? makeBookPlan()
            return Array(Set(displays.flatMap { display -> [Int] in
                let index = display + (previousChapter != nil ? 1 : 0)
                guard let group = plan.groupIndex(containingCanonicalIndex: index) else { return [] }
                return plan.groups[group].compactMap(\.canonicalIndex).filter { index in
                    guard pageViewControllers.indices.contains(index), case .page = pageViewControllers[index].type else { return false }
                    return true
                }
            })).sorted()
        }
        return Array(Set(displays.flatMap { presentationIndices(for: $0) })).sorted()
    }

    var sumiOpeningImageFailed: Bool {
        canonicalControllers(in: pageViewController.viewControllers ?? []).contains(where: \.sumiImageLoadFailed)
    }

    func sumiAbandonOpening() {
        viewModel.sumiCancelLoading()
        nextChapterPreloadTask?.cancel()
        nextChapterPreloadTask = nil
        pagePrefetcher.reset()
        pageViewControllers.forEach { $0.sumiReleasePreloadedImage() }
    }

    /// Opening waits for the actual selected chapter's visible artwork, rather
    /// than treating a page-list response or an offscreen prefetched image as ready.
    var sumiReadyForOpening: Bool {
        guard isViewLoaded, currentPage >= 1, !isTransitioning,
              let chapter, viewModel.chapter?.key == chapter.key,
              !viewModel.pages.isEmpty else { return false }
        let requested = sumiCurrentCanonicalPage
        let visible = pageViewController.viewControllers ?? []
        let containsRequested = canonicalControllers(in: visible).contains { page in
            guard case .page = page.type, let index = pageViewControllers.firstIndex(of: page),
                  actualPageIndex(from: pageIndex(from: index)) == requested else { return false }
            return page.pageView?.sumiIsImageReady == true
        }
        return containsRequested && leafControllers(in: visible).allSatisfy { leaf in
            if let page = leaf as? ReaderPageViewController {
                if case .info = page.type { return true }
                return page.pageView?.sumiIsImageReady == true
            }
            if let wide = leaf as? ReaderBookWideLeafViewController {
                return wide.canonicalController.pageView?.sumiIsImageReady == true && wide.sumiIsImageReady
            }
            return leaf is ReaderBookBlankViewController
        }
    }

    var sumiOpeningIndex: SumiReaderIndex? {
        didSet {
            sumiIndexLeaf = nil
            sumiDidPresentOpening = false
            bookPlanNeedsPagerReset = true
        }
    }
    var sumiSelectIndexChapter: ((AidokuRunner.Chapter) -> Void)?
    private var sumiIndexLeaf: SumiIndexLeafViewController?
    private var sumiDidPresentOpening = false
    private var sumiHasOpeningIndex: Bool { sumiOpeningIndex?.applies(to: chapter) == true }
    private var sumiFirstCanonicalIndex: Int { 1 + (previousChapter != nil ? 1 : 0) }
    var sumiIsShowingIndex: Bool { pageViewController.viewControllers?.first is SumiIndexLeafViewController }
    var sumiZoomTargetView: UIView? {
        leafControllers(in: pageViewController.viewControllers ?? []).first(where: {
            $0 is ReaderPageViewController || $0 is ReaderBookWideLeafViewController
        })?.view
    }

    private func sumiStandalone(_ controller: UIViewController) -> UIViewController {
        if controller.parent !== pageViewController { controller.remove() }
        if let index = controller as? SumiIndexLeafViewController { index.bookBindingEdge = .none }
        if let page = controller as? ReaderPageViewController { page.bookBindingEdge = .none }
        if let wide = controller as? ReaderBookWideLeafViewController { wide.bookBindingEdge = .none }
        if let layer = controller.viewIfLoaded?.layer {
            ReaderBookSpineView.removeBindingLighting(from: layer)
            layer.shadowOpacity = 0
            layer.shadowPath = nil
        }
        return controller
    }

    private func sumiReleaseBookPresentation() {
        // Native portrait paging can request any cached neighbor after a fold,
        // not only the leaf selected during the pager replacement. Retire all
        // spread-owned lighting before those canonical pages become standalone.
        for spread in bookSpreads.values { spread.releaseLeaves() }
        for page in pageViewControllers { page.bookBindingEdge = .none }
        for case let wide as ReaderBookWideLeafViewController in bookControllers.values {
            wide.bookBindingEdge = .none
        }
        sumiIndexLeaf?.bookBindingEdge = .none
        bookSpreads.removeAll()
        bookControllers.removeAll()
        bookCanonicalControllers.removeAll()
        bookPlan = nil
        bookSpineView.update(pageFrames: [], enabled: false)
    }

    private func sumiIndexController() -> SumiIndexLeafViewController? {
        guard let index = sumiOpeningIndex else { return nil }
        if let sumiIndexLeaf { return sumiIndexLeaf }
        let leaf = SumiIndexLeafViewController(index: index)
        leaf.onSelectChapter = { [weak self] chapter in self?.sumiSelectIndexChapter?(chapter) }
        sumiIndexLeaf = leaf
        return leaf
    }
#endif

    private var usesBookLayout: Bool {
        usesDoublePages && (readingMode == .ltr || readingMode == .rtl)
            && view.bounds.width > view.bounds.height
    }

    private var pagerContentFrame: CGRect {
#if SUMI
        SumiReaderPresentation.contentFrame(in: view.bounds,
            safeAreaInsets: view.window?.safeAreaInsets ?? view.safeAreaInsets,
            avoidsDisplayCutout: HonbakoDisplayCanvas.avoidsDisplayCutout(in: view))
#else
        view.bounds
#endif
    }

    private var displayedTransition: ReaderPageTransition {
        ReaderPageTransition(style: pageViewController.transitionStyle,
            orientation: pageViewController.navigationOrientation, spine: pageViewController.spineLocation)
    }

    private var desiredTransition: ReaderPageTransition {
#if SUMI
        // Sumi owns the curl. A scroll-style contract presents each pair as a
        // spread wrapper without UIKit reparenting individual paper surfaces.
        ReaderPageTransition(style: .scroll,
            orientation: readingMode == .vertical ? .vertical : .horizontal, spine: .none)
#else
        ReaderPageTransition.resolve(viewport: view.bounds.size, readingMode: readingMode,
                                     reduceMotion: reduceMotionEnabled(), paired: usesBookLayout)
#endif
    }

    #if SUMI
    private var sumiPresentation: SumiReaderPresentation {
        .resolve(viewport: view.bounds.size, readingMode: readingMode, reduceMotion: reduceMotionEnabled(),
                 sizingOverride: sumiPageSizingOverride)
    }

    private func usesCanonicalSlideDirection(_ pager: UIPageViewController) -> Bool {
        !(pager is SumiPageCurlViewController) && readingMode != .vertical
    }

    private func applySumiPageSizing() {
        guard !isTransitioning else { return }
        let sizing = sumiPresentation.pageSizing
        for page in pageViewControllers { page.sumiPageSizing = sizing }
        for case let wide as ReaderBookWideLeafViewController in bookControllers.values {
            wide.sumiPageSizing = sizing
        }
    }

    #endif

    private func pagerMatches(_ transition: ReaderPageTransition) -> Bool {
#if SUMI
        let wantsCustomCurl = sumiPresentation.usesCustomCurl
        let customPager = pageViewController as? SumiPageCurlViewController
        return transition.matches(pageViewController)
            && (customPager != nil) == wantsCustomCurl
            && (customPager == nil || customPager?.readingMode == readingMode)
#else
        return transition.matches(pageViewController)
#endif
    }

    private func makePager(for transition: ReaderPageTransition) -> UIPageViewController {
#if SUMI
        if sumiPresentation.usesCustomCurl {
            return SumiPageCurlViewController(readingMode: readingMode)
        }
#endif
        let controller = transition.makeController()
#if SUMI
        controller.view.accessibilityIdentifier = "sumi.reader.slide"
#endif
        return controller
    }

    private var dictionaryOverlayTapHandler: ((String, String, CGRect, [CGRect]) -> Void)?
    private var dictionaryOverlayInteractionMode: DictionaryOverlayInteractionMode = .none

    private var previousChapter: AidokuRunner.Chapter?
    private var nextChapter: AidokuRunner.Chapter?

    private lazy var pageViewController = makePageViewController()

    func makePageViewController() -> UIPageViewController {
#if SUMI
        if sumiPresentation.usesCustomCurl {
            return SumiPageCurlViewController(readingMode: readingMode)
        }
#endif
        let controller = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: readingMode == .vertical ? .vertical : .horizontal,
            options: nil
        )
#if SUMI
        controller.view.accessibilityIdentifier = "sumi.reader.slide"
#endif
        return controller
    }

    private func disableNativeCurlTaps() {
#if SUMI
        SumiReaderGesturePolicy.reservePinches(in: pageViewController.view)
        let pan = pageViewController is SumiPageCurlViewController || readingMode == .vertical
            ? nil : pageViewController.view.subviews.compactMap { $0 as? UIScrollView }.first?.panGestureRecognizer
        if sumiSlidePan !== pan {
            sumiSlidePan?.removeTarget(self, action: #selector(sumiNativeSlidePan(_:)))
            sumiSlidePan = pan
            sumiSlidePanStarted = false
            sumiPaperHaptics.cancel()
            pan?.addTarget(self, action: #selector(sumiNativeSlidePan(_:)))
            if pan != nil, view.window != nil { sumiPaperHaptics.prepare(in: view) }
        }
#endif
        guard pageViewController.transitionStyle == .pageCurl else { return }
        // Existing tap zones and toolbar taps remain the only tap navigation.
        for recognizer in pageViewController.gestureRecognizers where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
        }
    }

#if SUMI
    @objc private func sumiNativeSlidePan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            sumiSlidePanStarted = true
            sumiPaperHaptics.begin(distance: view.bounds.width, visible: view.window != nil, location: pan.location(in: view))
        case .changed:
            guard sumiSlidePanStarted else { return }
            sumiPaperHaptics.update(progress: abs(pan.translation(in: view).x) / max(1, view.bounds.width),
                velocity: pan.velocity(in: view).x, location: pan.location(in: view))
        case .ended, .cancelled, .failed:
            guard sumiSlidePanStarted else { return }
            sumiSlidePanStarted = false
            sumiPaperHaptics.release(velocity: pan.velocity(in: view).x, cancelled: pan.state != .ended)
        default: break
        }
    }
#endif

    private func updatePageTransitionIfNeeded() {
        guard isViewLoaded, !isRebuildingPageViewController else { return }
        let transition = desiredTransition
        guard !isTransitioning else {
            pendingPageTransitionRebuild = !pagerMatches(transition) || displayingBookLayout != usesBookLayout || pageGraphNeedsPagerReset
            return
        }
        guard !pagerMatches(transition) || displayingBookLayout != usesBookLayout
                || (usesBookLayout && bookPlanNeedsPagerReset) || pageGraphNeedsPagerReset else {
            pendingPageTransitionRebuild = false
            disableNativeCurlTaps()
            updateBookSpine()
            return
        }
        guard !(pageViewController.viewControllers ?? []).isEmpty, !pageViewControllers.isEmpty else {
            pendingPageTransitionRebuild = true
            return
        }
        #if SUMI
        let requestedPage = sumiCanonicalFocus?.chapterID == chapter?.id && actualPageIndex(from: currentPage) != sumiCurrentCanonicalPage
            ? firstDisplayPage(forActual: sumiCurrentCanonicalPage) : currentPage
        #else
        let requestedPage = currentPage
        #endif
        let controllers = presentationControllers(for: requestedPage, transition: transition)
        guard !controllers.isEmpty else { return }
        replacePager(with: transition, displaying: controllers)
    }

    private func leafControllers(in controllers: [UIViewController]) -> [UIViewController] {
        controllers.flatMap { controller in
            if let spread = controller as? ReaderBookSpreadViewController { return spread.leaves }
            return [controller]
        }
    }

    private func zoomView(in controller: UIViewController) -> ZoomableScrollView? {
        if let page = controller as? ReaderPageViewController { return page.zoomView }
        if let wide = controller as? ReaderBookWideLeafViewController { return wide.zoomView }
        return (controller as? ReaderDoublePageViewController)?.zoomView
    }

    private func prepareForPresentation(_ controllers: [UIViewController]) {
#if SUMI
        if !usesBookLayout { sumiReleaseBookPresentation() }
#endif
        // Legacy shared-zoom spreads move PageViews, so restore their canonical
        // scroll views before the whole page controllers become independent leaves.
        for old in pageViewController.viewControllers ?? [] {
#if SUMI
            // Our renderer still needs the settled leaves until it has captured
            // the front textures. Their wrapper owns them throughout the turn.
            if pageViewController is SumiPageCurlViewController { continue }
#endif
            if let spread = old as? ReaderBookSpreadViewController {
                if !controllers.contains(where: { $0 === spread }) { spread.releaseLeaves() }
            } else if let spread = old as? ReaderDoublePageViewController,
                      !controllers.contains(where: { $0 === spread }) {
                spread.releasePageViews()
            }
        }
        for controller in controllers {
#if SUMI
            controller.view.isHidden = false
#endif
            if let spread = controller as? ReaderBookSpreadViewController {
                spread.attachLeaves()
            } else {
                controller.remove()
                controller.view.translatesAutoresizingMaskIntoConstraints = true
#if SUMI
                if let index = controller as? SumiIndexLeafViewController { index.bookBindingEdge = .none }
#endif
                if let page = controller as? ReaderPageViewController {
                    #if SUMI
                    page.bookBindingEdge = .none
                    page.updatePaperShape()
                    #endif
                    page.pageView?.clearReferenceViewport()
                }
            }
        }
    }

    private func replacePager(with transition: ReaderPageTransition, displaying controllers: [UIViewController]) {
        pendingPageTransitionRebuild = false
        isRebuildingPageViewController = true
        defer { isRebuildingPageViewController = false }
#if SUMI
        // A fold can be deferred while a captured paper mesh is active. Apply
        // its final viewport policy now, before saving/restoring zoom state;
        // another parent layout pass is not required to finish that handoff.
        applySumiPageSizing()
#endif
        let visible = pageViewController.viewControllers ?? []
        let states = leafControllers(in: visible).compactMap { controller -> (ZoomableScrollView, CGSize, CGFloat, CGPoint)? in
            guard let zoom = zoomView(in: controller) else { return nil }
            return (zoom, zoom.bounds.size, zoom.zoomScale, zoom.contentOffset)
        }
        let previous = pageViewController
        previous.delegate = nil
        previous.dataSource = nil
        prepareForPresentation(controllers)
        previous.remove()
        for controller in controllers { controller.remove() }
        let replacement = makePager(for: transition)
        replacement.delegate = self
        replacement.setViewControllers(controllers, direction: .forward, animated: false)
        replacement.dataSource = self
        pageViewController = replacement
        pageGraphNeedsPagerReset = false
        displayingBookLayout = usesBookLayout
        bookPlanNeedsPagerReset = false
        disableNativeCurlTaps()
        add(child: replacement)
        replacement.view.frame = pagerContentFrame
        replacement.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        replacement.view.layoutIfNeeded()
#if SUMI
        if sumiHasOpeningIndex, usesBookLayout, currentPage == 0 {
            currentPage = 1
            delegate?.setCurrentPage(1, position: nil)
        } else if currentPage >= 1,
                  let index = canonicalControllers(in: controllers)
                    .compactMap({ pageViewControllers.firstIndex(of: $0) }).min() {
            currentPage = pageIndex(from: index)
        }
#endif
        disableNativeCurlTaps()
        // A style-only change keeps both independent viewports exactly. Resizing
        // leaves is handled by each scroll view's normalized position geometry.
        let activeZooms = Set(leafControllers(in: controllers).compactMap { zoomView(in: $0) }.map(ObjectIdentifier.init))
        for (zoom, size, scale, offset) in states where activeZooms.contains(ObjectIdentifier(zoom)) && zoom.bounds.size == size {
            zoom.setZoomScale(scale, animated: false)
            zoom.setContentOffset(offset, animated: false)
        }
        updateBookSpine()
    }

    private func makeBookPlan() -> ReaderBookPlan {
        var groups: [[Int]] = []
        var wide: Set<Int> = []
        var leadingBlanks: Set<Int> = []
        var index = 0
        while pageViewControllers.indices.contains(index) {
            let displayPage = pageIndex(from: index)
            let resolved = (0...displayPageCount + 1).contains(displayPage) ? presentationIndices(for: displayPage) : [index]
            let group = resolved.first == index ? resolved : [index]
            groups.append(group)
            if group.count == 1, case .page = pageViewControllers[index].type {
                if pageViewControllers[index].isWideImage, splitPages[actualPageIndex(from: displayPage)] == nil {
                    wide.insert(index)
                } else if isolatedPages.contains(displayPage), isPagePairable(displayPage) {
                    leadingBlanks.insert(index)
                }
            }
            index += max(1, group.count)
        }
#if SUMI
        return ReaderBookPlan(canonicalGroups: groups, wideIndices: wide, leadingBlankIndices: leadingBlanks,
            readingMode: bookLeafOrder, frontmatterIndex: sumiHasOpeningIndex ? sumiFirstCanonicalIndex : nil)
#else
        return ReaderBookPlan(canonicalGroups: groups, wideIndices: wide, leadingBlankIndices: leadingBlanks, readingMode: readingMode)
#endif
    }

    private func prepareBookPlan() {
        guard !isTransitioning else { return }
        let plan = makeBookPlan()
        let sameControllers = bookCanonicalControllers.count == pageViewControllers.count
            && zip(bookCanonicalControllers, pageViewControllers).allSatisfy { $0 === $1 }
        guard plan != bookPlan || !sameControllers else { return }
        // Resolving a different, preloaded wide page must not replace the live
        // clipping leaves (and independent zoom positions) of this original.
        func owner(of slot: ReaderBookPlan.Slot, in controllers: [ReaderPageViewController]) -> ReaderPageViewController? {
            let index: Int
            switch slot {
                case .page(let value), .wideLeft(let value), .wideRight(let value), .blank(let value): index = value
            }
            return controllers[safe: index]
        }
        func sameSurface(_ first: ReaderBookPlan.Slot, _ second: ReaderBookPlan.Slot) -> Bool {
            switch (first, second) {
                case (.page, .page), (.wideLeft, .wideLeft), (.wideRight, .wideRight), (.blank, .blank): true
                default: false
            }
        }
        var retained: [ReaderBookPlan.Slot: UIViewController] = [:]
        for slot in plan.slots {
            guard let canonical = owner(of: slot, in: pageViewControllers),
                  let old = bookControllers.first(where: {
                      sameSurface(slot, $0.key) && owner(of: $0.key, in: bookCanonicalControllers) === canonical
                  }) else { continue }
            retained[slot] = old.value
        }
        var retainedSpreads: [Int: ReaderBookSpreadViewController] = [:]
        for group in plan.groups.indices {
            let leaves = plan.physicalSlots(in: group, readingMode: bookLeafOrder).compactMap { retained[$0] }
            guard leaves.count == 2,
                  let spread = bookSpreads.values.first(where: { $0.leaves.elementsEqual(leaves, by: { $0 === $1 }) }) else { continue }
            retainedSpreads[group] = spread
        }
        bookPlan = plan
        bookPlanNeedsPagerReset = true
        bookCanonicalControllers = pageViewControllers
        bookControllers = retained
        bookSpreads = retainedSpreads
    }

    func bookController(for slot: ReaderBookPlan.Slot) -> UIViewController {
        if let cached = bookControllers[slot] { return cached }
        let controller: UIViewController
        switch slot {
            case .page(let index): controller = bookCanonicalControllers[index]
            case .blank(let index):
#if SUMI
                if sumiHasOpeningIndex, index == sumiFirstCanonicalIndex, let leaf = sumiIndexController() { controller = leaf }
                else { controller = ReaderBookBlankViewController() }
#else
                controller = ReaderBookBlankViewController()
#endif
            case .wideLeft(let index), .wideRight(let index):
                let wide = ReaderBookWideLeafViewController(canonicalController: bookCanonicalControllers[index],
                    side: { if case .wideLeft = slot { return .left }; return .right }())
                #if SUMI
                wide.sumiPageSizing = sumiPresentation.pageSizing
                #endif
                wide.loadViewIfNeeded()
                #if !SUMI
                wide.imageView.addInteraction(UIContextMenuInteraction(delegate: self))
                if #available(iOS 18.0, *) { bindDictionaryOverlayTap(to: wide) }
                #endif
                controller = wide
        }
        bookControllers[slot] = controller
        return controller
    }

    private func bookSlot(for controller: UIViewController) -> ReaderBookPlan.Slot? {
        bookControllers.first { $0.value === controller }?.key
    }

    private func bookGroup(for controller: UIViewController) -> Int? {
        if let spread = controller as? ReaderBookSpreadViewController {
            return spread.leaves.compactMap { bookSlot(for: $0) }.first.flatMap { bookPlan?.groupIndex(containing: $0) }
        }
        return bookSlot(for: controller).flatMap { bookPlan?.groupIndex(containing: $0) }
    }

    private func bookPresentation(group: Int, transition: ReaderPageTransition) -> [UIViewController] {
        guard let bookPlan else { return [] }
        let leaves = bookPlan.physicalSlots(in: group, readingMode: bookLeafOrder).map { bookController(for: $0) }
        guard transition.spine != .mid else { return leaves }
        if let spread = bookSpreads[group] { return [spread] }
        let spread = ReaderBookSpreadViewController(leaves: leaves)
        bookSpreads[group] = spread
        return [spread]
    }

    private func presentationControllers(for requestedPage: Int, transition: ReaderPageTransition) -> [UIViewController] {
#if SUMI
        if sumiHasOpeningIndex, requestedPage == 0, !usesBookLayout, let index = sumiIndexController() { return [index] }
        let page = sumiHasOpeningIndex && requestedPage == 0 && usesBookLayout ? 1 : requestedPage
#else
        let page = requestedPage
#endif
        if usesBookLayout {
            prepareBookPlan()
            let index = min(max(page, 0), displayPageCount + 1) + (previousChapter != nil ? 1 : 0)
            guard let group = bookPlan?.groupIndex(containingCanonicalIndex: index) else { return [] }
            return bookPresentation(group: group, transition: transition)
        }
        let indices = presentationIndices(for: page)
        guard let first = indices.first else { return [] }
        if indices.count == 2,
           let existing = pageViewController.viewControllers?.first as? ReaderDoublePageViewController,
           existing.firstPageController === pageViewControllers[first],
           existing.secondPageController === pageViewControllers[indices[1]],
           existing.direction == (readingMode == .rtl ? .rtl : .ltr) { return [existing] }
        if indices.count == 2, let spread = createPageController(firstPage: pageViewControllers[first],
            secondPage: pageViewControllers[indices[1]], page: pageIndex(from: first)) { return [spread] }
        #if SUMI
        return [sumiStandalone(pageViewControllers[first])]
        #else
        return [pageViewControllers[first]]
        #endif
    }

    private func updateBookSpine() {
#if SUMI
        guard usesBookLayout else {
            bookSpineView.update(pageFrames: [], enabled: false)
            return
        }
        if sumiChapterStateView != nil {
            bookSpineView.update(pageFrames: [], enabled: false)
            return
        }
        if pageViewController is SumiPageCurlViewController {
            // Curved paper masks form the seam; those very pixels deform with
            // their leaf. A stationary overlay would slice through the curl.
            bookSpineView.update(pageFrames: [], enabled: false)
            return
        }
#endif
        // The native curl temporarily moves and reparents its leaf surfaces.
        // Keep the binding at the last settled seam throughout that gesture.
        if isTransitioning {
            if displayingBookLayout, !bookSpineView.isHidden { view.bringSubviewToFront(bookSpineView) }
            return
        }
        let leaves = leafControllers(in: pageViewController.viewControllers ?? [])
        let frames = leaves.map { $0.view.convert($0.view.bounds, to: view) }
        bookSpineView.update(pageFrames: frames, enabled: displayingBookLayout)
        view.bringSubviewToFront(bookSpineView)
    }

    private func freezePagerViewport() {
        guard transitionPagerFrame == nil else { return }
        transitionPagerFrame = pageViewController.view.frame
        pageViewController.view.autoresizingMask = []
    }

    private func updatePageTurnCadence() {
        guard isViewLoaded else { return }
        pageTurnCadence?.setActive(isTransitioning && pageViewController.transitionStyle == .pageCurl && view.window != nil)
    }

    private func settlePagerViewport() {
        transitionPagerFrame = nil
        pageViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pageViewController.view.frame = pagerContentFrame
        pageViewController.view.layoutIfNeeded()
        updateBookSpine()
    }

    private func resetPageNavigationGesture() {
#if SUMI
        if pageViewController is SumiPageCurlViewController {
            for recognizer in pageViewController.gestureRecognizers {
                recognizer.isEnabled = false
                recognizer.isEnabled = true
            }
            return
        }
#endif
        if pageViewController.transitionStyle == .pageCurl {
            for recognizer in pageViewController.gestureRecognizers where recognizer is UIPanGestureRecognizer {
                recognizer.isEnabled = false
                recognizer.isEnabled = true
            }
            disableNativeCurlTaps()
        } else {
            for subview in pageViewController.view.subviews {
                guard let scrollView = subview as? UIScrollView else { continue }
                scrollView.panGestureRecognizer.isEnabled = false
                scrollView.panGestureRecognizer.isEnabled = true
                break
            }
        }
    }

    init(
        source: AidokuRunner.Source?,
        manga: AidokuRunner.Manga,
        temporaryPageStore: ReaderTemporaryPageStore,
        reduceMotionEnabled: @escaping () -> Bool = { UIAccessibility.isReduceMotionEnabled }
    ) {
        self.reduceMotionEnabled = reduceMotionEnabled
        self.viewModel = ReaderPagedViewModel(
            source: source,
            manga: manga,
            temporaryPageStore: temporaryPageStore
        )
        super.init()
    }

    override func configure() {
        pageViewController.delegate = self
        pageViewController.dataSource = self
        #if SUMI
        pageViewController.view.frame = pagerContentFrame
        pageViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        #endif
        add(child: pageViewController)

        view.addSubview(bookSpineView)
        pageTurnCadence = ReaderPageTurnCadence(view: view)
        updatePageLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updatePageTurnCadence()
        #if SUMI
        if !(pageViewController is SumiPageCurlViewController) { sumiPaperHaptics.prepare(in: view) }
        preloadNextChapter(pageCount: SumiNextChapterPreloadPolicy.firstPages)
        #endif
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pageTurnCadence?.setActive(false)
    }

    override func observe() {
        addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification) { [weak self] _ in
            self?.updatePageTransitionIfNeeded()
        }
        addObserver(forName: "Reader.pagedPageLayout") { [weak self] _ in
            guard let self = self else { return }
            self.updatePageLayout()
            guard !self.pageViewControllers.isEmpty else { return }
            self.move(toPage: self.currentPage, animated: false)
        }
        addObserver(forName: "Reader.pagesToPreload") { [weak self] notification in
            #if SUMI
            self?.pagesToPreload = SumiPagePreloadWindow.ahead
            #else
            self?.pagesToPreload = notification.object as? Int
                ?? UserDefaults.standard.integer(forKey: "Reader.pagesToPreload")
            #endif
        }
        addObserver(forName: UIApplication.didReceiveMemoryWarningNotification.rawValue) { [weak self] _ in
            // clear pages that aren't in the preload range if we get a memory warning
            LogManager.logger.warn("Received memory warning")
            Self.clearSplitPageCache()
            self?.pagePrefetcher.reset()
            guard
                let self,
                let visible = pageViewController.viewControllers
            else { return }
            let visibleIndices = canonicalControllers(in: visible).compactMap { self.pageViewControllers.firstIndex(of: $0) }
            guard let first = visibleIndices.min(), let last = visibleIndices.max() else { return }
            let safeRange = max(0, first - pagesToPreload)...min(pageViewControllers.count - 1, last + pagesToPreload)
            for (idx, controller) in pageViewControllers.enumerated() where !safeRange.contains(idx) {
                controller.clearPage()
            }
        }
        let refreshSplitPages: (Notification) -> Void = { [weak self] _ in
            guard let self, let chapter = self.chapter else { return }
            let actualPage = self.actualPageIndex(from: self.currentPage)
            let wasSplit = self.splitWideImages
            self.splitWideImages = UserDefaults.standard.bool(forKey: "Reader.splitWideImages")
            self.splitPages.removeAll()
            if wasSplit, self.splitWideImages {
                if let key = self.splitPageCacheKey {
                    self.reverseSplitStoreEntries(for: key)
                }
            }
            self.loadPageControllers(chapter: chapter)
            self.resetIsolation()
            let targetPage = max(1, min(self.firstDisplayPage(forActual: actualPage), self.displayPageCount))
            self.move(toPage: targetPage, animated: false)
        }
        addObserver(forName: "Reader.splitWideImages", using: refreshSplitPages)
        addObserver(forName: "Reader.reverseSplitOrder", using: refreshSplitPages)

        if let value = UserDefaults.standard.object(forKey: pageOffsetKey) as? Bool {
            pageOffsetEnabled = value
        } else {
            pageOffsetEnabled = UserDefaults.standard.bool(forKey: "Reader.pagedPageOffset")
        }

        addObserver(forName: pageOffsetKey) { [weak self] _ in
            guard let self, self.chapter != nil else { return }
            let newValue = UserDefaults.standard.bool(forKey: self.pageOffsetKey)

            guard self.pageOffsetEnabled != newValue else { return }
            self.pageOffsetEnabled = newValue

            self.resetIsolation()
            self.refreshChapter(startPage: self.currentPage)
        }
        addObserver(forName: "Reader.pagedPageOffset") { [weak self] _ in
            guard let self, self.chapter != nil else { return }
            // only follow global when no per-manga override exists
            guard UserDefaults.standard.object(forKey: self.pageOffsetKey) == nil else { return }
            let newValue = UserDefaults.standard.bool(forKey: "Reader.pagedPageOffset")

            guard self.pageOffsetEnabled != newValue else { return }
            self.pageOffsetEnabled = newValue

            self.resetIsolation()
            self.refreshChapter(startPage: self.currentPage)
        }

        addObserver(forName: .readerShowingBars) { [weak self] _ in
            self?.setLiveTextButtonHidden(false)
        }
        addObserver(forName: .readerHidingBars) { [weak self] _ in
            self?.setLiveTextButtonHidden(true)
        }
    }

    func updatePageLayout() {
#if SUMI
        usesAutoPageLayout = true
        usesDoublePages = sumiPresentation.usesDoublePages
        applySumiPageSizing()
#else
        usesDoublePages = {
            self.usesAutoPageLayout = false
            switch UserDefaults.standard.string(forKey: "Reader.pagedPageLayout") {
                case "single": return false
                case "double": return true
                case "auto":
                    self.usesAutoPageLayout = true
                    return self.view.bounds.width > self.view.bounds.height
                default: return false
            }
        }()
#endif
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        #if SUMI
        sumiPaperHaptics.suspend()
        sumiCancelAnimatedNavigation()
        nextChapterPreloadTask?.cancel()
        nextChapterPreloadTask = nil
        sumiPreparedNextChapterID = nil
        sumiNextChapterRetryAfter = .distantPast
        viewModel.sumiCancelPreload(except: viewModel.preloadedChapter)
        pagePrefetcher.reset()
        #endif
    }

    #if SUMI
    /// A rotation is a new paper layout, not a continuation of an old mesh.
    /// Resolve it synchronously before any leaf is reparented. Otherwise the
    /// frozen pager can keep its old size and a hidden pending leaf can survive
    /// inside the newly mounted spread.
    private func sumiAdaptToViewportChange() {
        guard !sumiIsAdaptingViewport else { return }
        sumiIsAdaptingViewport = true
        defer { sumiIsAdaptingViewport = false }
        sumiPaperHaptics.cancel()
        sumiSlidePanStarted = false
        sumiCancelAnimatedNavigation()
        (pageViewController as? SumiPageCurlViewController)?.cancelCurrentTurn()
        let canonicalPage = sumiCurrentCanonicalPage
        let splitOffset = max(0, currentPage - firstDisplayPage(forActual: canonicalPage))
        if let chapter, canonicalPage > 0, canonicalPage <= viewModel.pages.count {
            sumiCanonicalFocus = (chapter.id, canonicalPage)
        }
        isTransitioning = false
        programmaticMove = false
        pendingPageMove = nil
        sumiQueuedCanonicalFocus = nil
        transitionPagerFrame = nil
        pageViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        usesDoublePages = sumiPresentation.usesDoublePages
        applySumiPageSizing()
        pendingSpreadRebuild = false
        guard !pageViewControllers.isEmpty else { return }
        let displayPage = canonicalPage > 0 && canonicalPage <= viewModel.pages.count
            ? min(firstDisplayPage(forActual: canonicalPage) + splitOffset, lastDisplayPage(forActual: canonicalPage)) : currentPage
        move(toPage: displayPage, animated: false, resetGesture: true)
        settlePagerViewport()
    }
    #endif

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isRebuildingPageViewController, view.bounds.width > 0, view.bounds.height > 0 else { return }
        #if SUMI
        guard !sumiIsAdaptingViewport else { return }
        // A chapter fetch has no page identity to remount yet. Its loading or
        // retry surface adapts immediately; the pages reconcile after success.
        if sumiChapterStateView != nil {
            sumiChapterStateView?.frame = view.bounds
            return
        }
        if sumiLastLayoutSize != view.bounds.size {
            let hadViewport = sumiLastLayoutSize != .zero
            sumiLastLayoutSize = view.bounds.size
            if hadViewport { sumiAdaptToViewportChange() }
        }
        #endif
#if SUMI
        if !isTransitioning, pageViewController.view.frame != pagerContentFrame {
            pageViewController.view.frame = pagerContentFrame
        }
        applySumiPageSizing()
#endif
        if usesAutoPageLayout {
#if SUMI
            let double = sumiPresentation.usesDoublePages
#else
            let double = view.bounds.width > view.bounds.height
#endif
            if usesDoublePages != double {
                usesDoublePages = double
                pendingSpreadRebuild = true
            }
        }
        if isTransitioning, let frame = transitionPagerFrame, pageViewController.view.frame != frame {
            pageViewController.view.frame = frame
        }
        updatePageTransitionIfNeeded()
        updateBookSpine()
        guard pendingSpreadRebuild, !isTransitioning, !pageViewControllers.isEmpty else { return }
        pendingSpreadRebuild = false
        if !visiblePresentationMatchesCurrentLayout() {
            move(toPage: currentPage, animated: false, resetGesture: false)
        }
    }

}

extension ReaderPagedViewController {
    func loadPageControllers(chapter: AidokuRunner.Chapter) {
        guard !viewModel.pages.isEmpty else { return } // TODO: handle zero pages
        #if SUMI
        sumiCancelAnimatedNavigation()
        #endif

        // if transitioning from an adjacent chapter, keep the existing pages
        var firstPageController: ReaderPageViewController?
        var lastPageController: ReaderPageViewController?
        var nextChapterPreviewController: ReaderPageViewController?
        var previousChapterPreviewController: ReaderPageViewController?
        if chapter == previousChapter {
            lastPageController = pageViewControllers.first
            nextChapterPreviewController = pageViewControllers[2]

            if let previousPreviewSplitPages {
                splitPages[viewModel.pages.count] = previousPreviewSplitPages
                self.previousPreviewSplitPages = nil
            }
        } else if chapter == nextChapter {
            firstPageController = pageViewControllers.last
            previousChapterPreviewController = pageViewControllers[pageViewControllers.count - 3]

            if let nextPreviewSplitPages {
                splitPages[1] = nextPreviewSplitPages
                self.nextPreviewSplitPages = nil
            }
        }

        pageViewControllers = []

        if splitWideImages {
            restoreCachedSplitPages()
        }

        previousChapter = delegate?.getPreviousChapter()

        // last page of previous chapter
        if previousChapter != nil {
            if let previousChapterPreviewController {
                pageViewControllers.append(previousChapterPreviewController)
            } else {
                pageViewControllers.append(
                    makePageController(
                        hasImageCallbacks: true,
                        preloadPage: previousPreviewSplitPages?.last
                    )
                )
            }
        }

        // previous chapter transition page
        let previousInfoController = ReaderPageViewController(type: .info(.previous), delegate: delegate)
        previousInfoController.currentChapter = chapter
        previousInfoController.previousChapter = previousChapter
        #if SUMI
        previousInfoController.sumiContinueChapter = { [weak self] in
            guard let self, let previous = self.previousChapter else { return }
            self.delegate?.setChapter(previous)
            self.setChapter(previous, startPage: 1)
        }
        #endif
        pageViewControllers.append(previousInfoController)

        // chapter pages
        let startPos = firstPageController != nil ? 1 : 0
        let endPos = viewModel.pages.count - (lastPageController != nil ? 1 : 0)

        if let firstPageController {
            if let splitPageArray = splitPages[1] {
                pageViewControllers.append(contentsOf: splitPageArray.map { makePageController(preloadPage: $0, skipProcessing: true) })
            } else {
                pageViewControllers.append(firstPageController)
            }
        }

        for i in startPos..<endPos {
            let originalPageIndex = i + 1
            if let splitPageArray = splitPages[originalPageIndex] {
                pageViewControllers.append(contentsOf: splitPageArray.map { makePageController(preloadPage: $0, skipProcessing: true) })
            } else {
                pageViewControllers.append(makePageController(hasImageCallbacks: true))
            }
        }

        if let lastPageController {
            if let splitPageArray = splitPages[viewModel.pages.count] {
                pageViewControllers.append(contentsOf: splitPageArray.map { makePageController(preloadPage: $0, skipProcessing: true) })
            } else {
                pageViewControllers.append(lastPageController)
            }
        }

        nextChapter = delegate?.getNextChapter()

        // next chapter transition page
        let nextInfoController = ReaderPageViewController(type: .info(.next), delegate: delegate)
        nextInfoController.currentChapter = chapter
        nextInfoController.nextChapter = nextChapter
        #if SUMI
        nextInfoController.sumiContinueChapter = { [weak self] in
            guard let self, let next = self.nextChapter else { return }
            self.delegate?.setChapter(next)
            self.setChapter(next, startPage: 1)
        }
        #endif
        pageViewControllers.append(nextInfoController)

        // first page of next chapter
        if nextChapter != nil {
            if let nextChapterPreviewController {
                pageViewControllers.append(nextChapterPreviewController)
            } else {
                pageViewControllers.append(
                    makePageController(
                        hasImageCallbacks: true,
                        preloadPage: nextPreviewSplitPages?.first
                    )
                )
            }
            #if SUMI
            // A pager refresh may create a new preview after its list has
            // already been prepared. Attach the cached cover immediately.
            if viewModel.preloadedChapter?.id == nextChapter?.id,
               let cover = viewModel.preloadedPages.first {
                pageViewControllers.last?.setPage(cover, sourceId: viewModel.manga.sourceKey)
            }
            #endif
        }

        rebuildPageIndices()
        #if SUMI
        // A chapter change publishes a new neighbor graph even when its first
        // controller is the same preview already visible at the old boundary.
        // UIKit otherwise keeps that preview's cached nil next neighbor, and
        // the same-controller move below cannot make the new chapter swipeable.
        pageGraphNeedsPagerReset = !(pageViewController is SumiPageCurlViewController)
        #endif
    }

    private func makePageController(
        hasImageCallbacks: Bool = false,
        preloadPage: Page? = nil,
        skipProcessing: Bool = false
    ) -> ReaderPageViewController {
        let page = ReaderPageViewController(
            type: .page,
            delegate: delegate,
            temporaryPageStore: viewModel.temporaryPageStore
        )
        #if SUMI
        page.sumiPageSizing = sumiPresentation.pageSizing
        #endif
        #if !SUMI
        page.pageView?.imageView.addInteraction(UIContextMenuInteraction(delegate: self))
        if #available(iOS 18.0, *) {
            bindDictionaryOverlayTap(to: page)
        }
        #endif
        page.pageView?.onReferenceContentChanged = { [weak self, weak page] in
            guard let self, let page else { return }
            for case let wide as ReaderBookWideLeafViewController in self.bookControllers.values
                where wide.canonicalController === page { wide.refreshImage() }
        }
        if hasImageCallbacks {
            page.onImageisWideImage = { [weak self, weak page] isWide in
                guard let self, let page, isWide else { return }
                guard let vcIndex = self.pageViewControllers.firstIndex(of: page) else { return }
                let liveDisplay = self.pageIndex(from: vcIndex)
                let actualPage = self.actualPageIndex(from: liveDisplay)
                if self.splitWideImages {
                    self.checkAndSplitWideImage(at: actualPage, controller: page)
                } else if
                    self.usesDoublePages,
                    abs(liveDisplay - self.currentPage) <= self.pagesToPreload
                {
                    self.adjustAutoIsolation()
                    if self.isTransitioning {
                        self.pendingSpreadRebuild = true
                    } else {
                        self.move(toPage: self.currentPage, animated: false, resetGesture: true)
                    }
                }
            }
            page.onAspectRatioUpdated = { [weak self, weak page] in
                guard let self, let page else { return }
                self.handleAspectRatioUpdate(from: page)
            }
        }
        if let preloadPage {
            page.setPage(preloadPage, skipProcessing: skipProcessing)
        }
        return page
    }

    /// Resolve grouping without constructing a wrapper or reparenting artwork.
    /// This is shared by moves and deferred layout checks so a fold that returns
    /// to its starting layout does not recreate an already-correct spread.
    private func presentationIndices(for page: Int) -> [Int] {
        let page = min(max(page, 0), displayPageCount + 1)
        let index = page + (previousChapter != nil ? 1 : 0)
        guard pageViewControllers.indices.contains(index) else { return [] }
        guard usesDoublePages else { return [index] }
        #if SUMI
        // The chapter boundary and the following chapter's cover form one
        // physical spread. Keep that same spread after ownership passes to the
        // next chapter, so turning again starts at its second displayed page.
        if previousChapter != nil, (0...1).contains(page) {
            return [1, 2]
        }
        if nextChapter != nil, page == displayPageCount + 1 {
            return [index, index + 1]
        }
        #endif
        func canPair(at first: Int) -> Bool {
            guard pageViewControllers.indices.contains(first), pageViewControllers.indices.contains(first + 1),
                  case .page = pageViewControllers[first].type,
                  case .page = pageViewControllers[first + 1].type else { return false }
            let displayPage = pageIndex(from: first)
            return spreadStart(for: displayPage) == displayPage
                && canDisplayAsDoublePage(displayPage) && canDisplayAsDoublePage(displayPage + 1)
        }
        let lastContentIndex = pageViewControllers.count - (nextChapter != nil ? 1 : 0) - 1
        if index + 1 <= lastContentIndex, canPair(at: index) {
            return [index, index + 1]
        }
        if index - 1 >= (previousChapter != nil ? 2 : 1), canPair(at: index - 1) {
            return [index - 1, index]
        }
        return [index]
    }

    private func visiblePresentationMatchesCurrentLayout() -> Bool {
        guard let visible = pageViewController.viewControllers else { return false }
#if SUMI
        if !usesBookLayout, sumiHasOpeningIndex, currentPage == 0 { return visible.first is SumiIndexLeafViewController }
#endif
        if usesBookLayout {
            let plan = makeBookPlan()
            guard plan == bookPlan,
                  let group = plan.groupIndex(containingCanonicalIndex: min(max(currentPage, 0), displayPageCount + 1) + (previousChapter != nil ? 1 : 0)) else { return false }
            let expected = plan.physicalSlots(in: group, readingMode: bookLeafOrder)
            let actual = leafControllers(in: visible).compactMap { bookSlot(for: $0) }
            return actual == expected
        }
        guard visible.count == 1 else { return false }
        let indices: [Int]
        if let spread = visible[0] as? ReaderDoublePageViewController {
            guard spread.direction == (readingMode == .rtl ? .rtl : .ltr),
                  let first = getIndex(of: spread, pos: .first), let second = getIndex(of: spread, pos: .second) else { return false }
            indices = [first, second]
        } else if let single = visible[0] as? ReaderPageViewController, let index = getIndex(of: single) {
            indices = [index]
        } else { return false }
        return indices == presentationIndices(for: currentPage)
    }

    func move(toPage page: Int, animated: Bool, resetGesture: Bool = true, didComplete: ((Bool) -> Void)? = nil) {
        guard !isTransitioning else {
            if let didComplete { didComplete(false); return }
            pendingPageMove = (page, animated, resetGesture, chapter?.id)
            return
        }
        let page = min(max(page, 0), displayPageCount + 1)
        let transition = desiredTransition
        let targets = presentationControllers(for: page, transition: transition)
        guard !targets.isEmpty else { didComplete?(false); return }
        #if SUMI
        let canonicalSlide = !sumiPresentation.usesCustomCurl && readingMode != .vertical
        let forward = canonicalSlide ? currentPage < page : (readingMode == .rtl ? currentPage > page : currentPage < page)
        #else
        let forward = readingMode == .rtl ? currentPage > page : currentPage < page
        #endif
        let previous = pageViewController.viewControllers ?? []
        let needsReplacement = !pagerMatches(transition) || displayingBookLayout != usesBookLayout
            || (usesBookLayout && bookPlanNeedsPagerReset) || pageGraphNeedsPagerReset
        if needsReplacement { replacePager(with: transition, displaying: targets) }
        isTransitioning = true
        programmaticMove = true
#if !SUMI
        currentPage = page
#endif
        if animated { freezePagerViewport() }
        updateBookSpine()
        if !animated, resetGesture { resetPageNavigationGesture() }
        let activePager = pageViewController
#if SUMI
        let animationOwner = sumiAnimationStepOwner
#endif
        let completion: (Bool) -> Void = { [weak self, weak activePager] completed in
            guard let self, let activePager, activePager === self.pageViewController else { didComplete?(false); return }
#if SUMI
            if let animationOwner {
                guard self.sumiAnimationStepOwner == animationOwner else { didComplete?(false); return }
                if completed, let navigation = self.sumiSlideNavigation, let chapter = self.chapter {
                    self.sumiCanonicalFocus = (chapter.id, navigation.destinationPage)
                }
            }
#endif
            self.pageViewController(activePager, didFinishAnimating: true,
                previousViewControllers: previous, transitionCompleted: completed)
            didComplete?(completed)
        }
        let same = (pageViewController.viewControllers ?? []).elementsEqual(targets, by: { $0 === $1 })
        if needsReplacement || same { completion(true); return }
        prepareForPresentation(targets)
        displayingBookLayout = usesBookLayout
        pageViewController.setViewControllers(targets, direction: forward ? .forward : .reverse,
                                              animated: animated, completion: completion)
        disableNativeCurlTaps()
    }

    func loadPage(at index: Int) {
        guard index > 0, index <= displayPageCount else { return }

        let actualPageIndex = actualPageIndex(from: index)
        guard actualPageIndex > 0, actualPageIndex <= viewModel.pages.count else { return }

        let vcIndex = index + (previousChapter != nil ? 1 : 0)
        guard vcIndex < pageViewControllers.count else { return }

        let targetVC = pageViewControllers[vcIndex]
        let sourceId = viewModel.source?.key ?? viewModel.manga.sourceKey

        if let splitPageArray = splitPages[actualPageIndex] {
            let splitIndex = splitIndex(for: index, actualPageIndex: actualPageIndex)
            if splitIndex < splitPageArray.count {
                targetVC.setPage(splitPageArray[splitIndex], sourceId: sourceId)
            }
        } else {
            targetVC.setPage(viewModel.pages[actualPageIndex - 1], sourceId: sourceId)
        }
    }

    func loadPages(in range: ClosedRange<Int>) {
        for i in range {
            guard i > 0 else { continue }
            guard i <= displayPageCount else { break }
            loadPage(at: i)
        }
        // allow prefetching into the next chapter
        if range.upperBound > displayPageCount {
            preloadNextChapter(pageCount: min(range.upperBound - displayPageCount, pagesToPreload))
        }
    }

    #if SUMI
    private func sumiPreloadNeighborhood(around page: Int, discardDistantPages: Bool) {
        guard let range = SumiPagePreloadWindow.range(around: page,
            visibleCount: usesDoublePages ? 2 : 1, total: displayPageCount) else { return }
        // Start the page the reader is arriving at before its future neighbors.
        loadPage(at: page)
        let nextPage = max(1, page + 1)
        if nextPage <= range.upperBound {
            for next in nextPage...range.upperBound { loadPage(at: next) }
        }
        for previous in stride(from: min(page - 1, range.upperBound), through: range.lowerBound, by: -1) {
            loadPage(at: previous)
        }
        if range.upperBound == displayPageCount {
            preloadNextChapter(pageCount: SumiPagePreloadWindow.ahead)
        }
        guard discardDistantPages, !isTransitioning, !sumiSequenceIsActive else { return }
        let visible = canonicalControllers(in: pageViewController.viewControllers ?? [])
        for (index, controller) in pageViewControllers.enumerated() {
            guard case .page = controller.type,
                  // Neighbor previews are the only artwork on a boundary
                  // spread. Keep these two small, bounded surfaces resident.
                  (1...displayPageCount).contains(pageIndex(from: index)),
                  !range.contains(pageIndex(from: index)),
                  !visible.contains(where: { $0 === controller }) else { continue }
            controller.sumiReleasePreloadedImage()
        }
    }
    #endif

    /// Fetch the first `pageCount` pages of the next chapter ahead of time.
    func preloadNextChapter(pageCount: Int) {
        guard pageCount > 0, let nextChapter else { return }

        #if SUMI
        guard chapter?.id == viewModel.chapter?.id,
              SumiNextChapterPreloadPolicy.shouldPrepare(page: actualPageIndex(from: currentPage),
                total: viewModel.pages.count, visibleCount: usesDoublePages ? 2 : 1),
              sumiNextChapterRetryAfter <= .now,
              sumiPreparedNextChapterID != nextChapter.id else { return }
        let currentChapterID = chapter?.id
        sumiPreparedNextChapterID = nextChapter.id
        nextChapterPreloadTask?.cancel()
        nextChapterPreloadTask = Task { [weak self] in
            guard let self else { return }
            let pages = await viewModel.preload(chapter: nextChapter)
            guard !Task.isCancelled, chapter?.id == currentChapterID,
                  self.nextChapter?.id == nextChapter.id, sumiPreparedNextChapterID == nextChapter.id else { return }
            guard !pages.isEmpty else {
                sumiPreparedNextChapterID = nil
                sumiNextChapterRetryAfter = .now.addingTimeInterval(SumiNextChapterPreloadPolicy.retryDelay)
                return
            }
            if let firstPage = pages.first, let preview = pageViewControllers.last,
               case .page = preview.type {
                preview.setPage(firstPage, sourceId: viewModel.manga.sourceKey)
            }
            await pagePrefetcher.prefetch(pages: pages, count: SumiNextChapterPreloadPolicy.firstPages,
                chapterKey: nextChapter.key, sourceKey: viewModel.manga.sourceKey,
                downsampleWidth: view.bounds.width / (usesDoublePages ? 2 : 1),
                displayScale: view.traitCollection.displayScale)
        }
        #else

        let previousTask = nextChapterPreloadTask
        nextChapterPreloadTask = Task { [weak self] in
            // preloads run one at a time so a wider range doesn't duplicate a narrower one in flight
            await previousTask?.value
            guard let self, !Task.isCancelled, nextChapter == self.nextChapter else { return }

            await viewModel.preload(chapter: nextChapter)

            guard
                !Task.isCancelled,
                nextChapter == self.nextChapter,
                viewModel.preloadedChapter == nextChapter
            else { return }

            let pages = viewModel.preloadedPages
            guard !pages.isEmpty else { return }
            let sourceKey = viewModel.manga.sourceKey

            if
                let firstPage = pages.first,
                let previewController = pageViewControllers.last,
                case .page = previewController.type
            {
                previewController.setPage(firstPage, sourceId: sourceKey)
            }

            await pagePrefetcher.prefetch(
                pages: pages,
                count: pageCount,
                chapterKey: nextChapter.key,
                sourceKey: sourceKey
            )
        }
        #endif
    }

    enum PagePosition {
        case first
        case second
    }

    func getIndex(of viewController: UIViewController, pos: PagePosition = .first) -> Int? {
        let controllers = canonicalControllers(in: [viewController])
        let indices = controllers.compactMap { pageViewControllers.firstIndex(of: $0) }.sorted()
        return pos == .first ? indices.first : indices.last
    }

    private func canonicalControllers(in controllers: [UIViewController]) -> [ReaderPageViewController] {
        var seen: Set<ObjectIdentifier> = []
        return leafControllers(in: controllers).flatMap { controller -> [ReaderPageViewController] in
            if let page = controller as? ReaderPageViewController { return [page] }
            if let wide = controller as? ReaderBookWideLeafViewController { return [wide.canonicalController] }
            if let spread = controller as? ReaderDoublePageViewController { return [spread.firstPageController, spread.secondPageController] }
            return []
        }.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    func visibleActualPageRange(in controller: UIViewController) -> ClosedRange<Int>? {
        visibleActualPageRange(in: [controller])
    }

    func visibleActualPageRange(in controllers: [UIViewController]) -> ClosedRange<Int>? {
        let pages = canonicalControllers(in: controllers).compactMap { page -> Int? in
            guard case .page = page.type, let index = pageViewControllers.firstIndex(of: page) else { return nil }
            let displayPage = pageIndex(from: index)
            guard displayPage >= 1, displayPage <= displayPageCount else { return nil }
            return actualPageIndex(from: displayPage)
        }
        guard let first = pages.min(), let last = pages.max() else { return nil }
        return first...last
    }

    func pageIndex(from index: Int) -> Int {
        index + (previousChapter != nil ? -1 : 0)
    }

    private func rebuildPageIndices() {
        guard !viewModel.pages.isEmpty else {
            actualPageIndices = []
            return
        }
        actualPageIndices = (1...viewModel.pages.count).flatMap {
            Array(repeating: $0, count: splitPages[$0]?.count ?? 1)
        }
    }

    /// Convert display page index to actual page index, accounting for split pages
    func actualPageIndex(from displayIndex: Int) -> Int {
        let index = displayIndex - 1
        guard actualPageIndices.indices.contains(index) else { return displayIndex }
        return actualPageIndices[index]
    }

    var displayPageCount: Int {
        actualPageIndices.count
    }

    private func splitIndex(for displayPage: Int, actualPageIndex: Int) -> Int {
        let segmentStart = actualPageIndices.firstIndex(of: actualPageIndex) ?? (displayPage - 1)
        return (displayPage - 1) - segmentStart
    }

    private func isPagePairable(_ page: Int) -> Bool {
        guard page >= 1, page <= displayPageCount else { return false }
        if manuallyIsolatedPages.contains(page) { return false }
        let vcIndex = page + (previousChapter != nil ? 1 : 0)
        guard pageViewControllers.indices.contains(vcIndex) else { return false }
        let vc = pageViewControllers[vcIndex]
        guard case .page = vc.type else { return false }
        let actual = actualPageIndex(from: page)
        if splitPages[actual] == nil, vc.isWideImage || hasCachedSplit(actual) {
            return false
        }
        return true
    }

    private func canDisplayAsDoublePage(_ page: Int) -> Bool {
        isPagePairable(page) && !isPageIsolated(page)
    }

    private func segmentHeadForPage(_ page: Int) -> Int {
        var head = page
        while head > 1 && isPagePairable(head - 1) { head -= 1 }
        return head
    }

    private func spreadStart(for page: Int, head: Int? = nil) -> Int {
        guard page >= 1, page <= displayPageCount, canDisplayAsDoublePage(page) else { return page }

        let segHead = head ?? segmentHeadForPage(page)
        let delta = page - segHead
        if isPageIsolated(segHead) {
            guard delta > 0 else { return segHead }
            return ((delta - 1) % 2 == 0) ? page : page - 1
        }
        return (delta % 2 == 0) ? page : page - 1
    }

    private func createPageController(
        firstPage: ReaderPageViewController,
        secondPage: ReaderPageViewController,
        page: Int
    ) -> ReaderDoublePageViewController? {
        guard
            canDisplayAsDoublePage(page),
            canDisplayAsDoublePage(page + 1)
        else { return nil }
        return ReaderDoublePageViewController(
            firstPage: firstPage,
            secondPage: secondPage,
            direction: readingMode == .rtl ? .rtl : .ltr
        )
    }

    private func handleAspectRatioUpdate(from source: ReaderPageViewController) {
        guard
            usesDoublePages,
            !isTransitioning,
            let doubleVC = pageViewController.viewControllers?.first as? ReaderDoublePageViewController,
            doubleVC.firstPageController == source || doubleVC.secondPageController == source
        else { return }

        if splitWideImages && source.isWideImage { return }

        move(toPage: currentPage, animated: false)
    }

    private func makeSplitPages(leftImage: UIImage, rightImage: UIImage, pageIndex: Int, sourcePage: Page? = nil) -> [Page] {
        let sourceId = viewModel.source?.key ?? viewModel.manga.sourceKey
        let reverseOrderSetting = UserDefaults.standard.bool(forKey: "Reader.reverseSplitOrder")
        let reverseOrder = readingMode == .rtl ? reverseOrderSetting : !reverseOrderSetting
        let originalPage = sourcePage ?? viewModel.pages[safe: pageIndex - 1] ?? viewModel.pages.first
        let chapterId = originalPage?.chapterId ?? chapter?.id ?? ""

        let leftPage = Page(
            sourceId: sourceId,
            chapterId: chapterId,
            index: originalPage?.index ?? max(0, pageIndex - 1),
            image: leftImage,
            language: originalPage?.language
        )
        let rightPage = Page(
            sourceId: sourceId,
            chapterId: chapterId,
            index: originalPage?.index ?? max(0, pageIndex - 1),
            image: rightImage,
            language: originalPage?.language
        )
        return reverseOrder ? [leftPage, rightPage] : [rightPage, leftPage]
    }

    private func storeSplitPages(left: UIImage, right: UIImage, at pageIndex: Int) {
        let pages = makeSplitPages(leftImage: left, rightImage: right, pageIndex: pageIndex)
        splitPages[pageIndex] = pages
        cacheSplitPages(pages, at: pageIndex)
    }

    /// Check if a wide image should be split and handle the splitting
    private func checkAndSplitWideImage(at pageIndex: Int, controller: ReaderPageViewController) {
        guard
            splitWideImages,
            splitPages[pageIndex] == nil,
            controller.isWideImage,
            pageViewControllers.contains(controller),
            let (leftImage, rightImage) = controller.pageView?.splitImage()
        else { return }

        if pageIndex <= 0 || pageIndex > viewModel.pages.count {
            let pages = makeSplitPages(leftImage: leftImage, rightImage: rightImage, pageIndex: pageIndex, sourcePage: controller.page)
            if pageIndex <= 0 {
                previousPreviewSplitPages = pages
            } else {
                nextPreviewSplitPages = pages
            }
            return
        }
        storeSplitPages(left: leftImage, right: rightImage, at: pageIndex)
        rebuildPageIndices()
        guard let stored = splitPages[pageIndex] else { return }
        applySplit(replacing: controller, with: stored)
    }

    private func applySplit(
        replacing controller: ReaderPageViewController,
        with stored: [Page]
    ) {
        guard
            stored.count >= 2,
            let replacingIndex = pageViewControllers.firstIndex(of: controller)
        else { return }

        controller.onImageisWideImage = nil
        controller.clearPage()
        if let image = stored[0].image {
            controller.pageView?.imageView.image = image
            controller.pageView?.fixImageSize()
        }
        controller.setPage(stored[0], skipProcessing: true)

        let newVCs = stored.dropFirst().map { makePageController(preloadPage: $0, skipProcessing: true) }
        pageViewControllers.insert(contentsOf: newVCs, at: replacingIndex + 1)
        #if SUMI
        // UIKit's sliding pager caches its adjacent controller. Inserting a
        // second half must invalidate that graph, even when the current print
        // itself did not change; otherwise a swipe can skip the new leaf.
        pageGraphNeedsPagerReset = !(pageViewController is SumiPageCurlViewController)
        #endif

        let splitDisplayPage = pageIndex(from: replacingIndex)
        shiftIsolation(after: splitDisplayPage, by: newVCs.count)

        if splitDisplayPage < currentPage {
            currentPage += newVCs.count
        }

        if isTransitioning {
            pendingSpreadRebuild = true
        } else {
            move(toPage: currentPage, animated: false, resetGesture: false)
        }
    }

    private func shiftIsolation(after displayPage: Int, by shift: Int) {
        guard shift > 0 else { return }
        isolatedPages = Set(isolatedPages.map { $0 > displayPage ? $0 + shift : $0 })
        manuallyIsolatedPages = Set(manuallyIsolatedPages.map { $0 > displayPage ? $0 + shift : $0 })
    }

    private func firstDisplayPage(forActual actualIndex: Int) -> Int {
        actualPageIndices.firstIndex(of: actualIndex).map { $0 + 1 } ?? actualIndex
    }

    private func lastDisplayPage(forActual actualIndex: Int) -> Int {
        actualPageIndices.lastIndex(of: actualIndex).map { $0 + 1 } ?? actualIndex
    }

    private func setLiveTextButtonHidden(_ hidden: Bool) {
        for controller in leafControllers(in: pageViewController.viewControllers ?? []) {
            if let page = controller as? ReaderPageViewController {
                page.pageView?.setLiveTextHidden(hidden || page.zoomView?.zoomScale != 1)
            } else if let wide = controller as? ReaderBookWideLeafViewController {
                wide.setLiveTextHidden(hidden || wide.zoomView.zoomScale != 1)
            } else if let spread = controller as? ReaderDoublePageViewController {
                for page in [spread.firstPageController, spread.secondPageController] {
                    page.pageView?.setLiveTextHidden(hidden || spread.zoomView.zoomScale != 1)
                }
            }
        }
    }

}

// MARK: - Page Offset
extension ReaderPagedViewController {
    func toggleOffset() {
        guard !isTransitioning, canToggleOffset() else { return }

        let head = findSegmentHead()
        guard isPagePairable(head) else { return }

        let wasIsolated = isPageIsolated(head)
        setPageIsolated(head, isolated: !wasIsolated)

        // other segment heads are toggled independently
        if head == firstToggleableHead() {
            pageOffsetEnabled = !wasIsolated
            UserDefaults.standard.set(!wasIsolated, forKey: pageOffsetKey)
        }

        let targetPage: Int
        if currentPage < head {
            targetPage = currentPage
        } else {
            let reference = wasIsolated
                ? min(currentPage + 1, displayPageCount)
                : currentPage
            targetPage = spreadStart(for: reference, head: head)
        }
        move(toPage: targetPage, animated: false)
    }

    private func firstToggleableHead() -> Int {
        let end = min(8, displayPageCount)
        guard end >= 2 else { return 0 }
        guard let first = (1...end).first(where: { isPagePairable($0) }) else { return 0 }
        // skip offset if the first pairable page is sandwiched by non-pairable pages
        return isPagePairable(first + 1) ? first : 0
    }

    private func findSegmentHead() -> Int {
        var head = currentPage
        while head <= displayPageCount && !isPagePairable(head) { head += 1 }
        while head > 1 && isPagePairable(head - 1) { head -= 1 }

        // skip single-page segments where toggling offset has no effect
        while head < displayPageCount && isPagePairable(head) && !isPagePairable(head + 1) {
            var next = head + 1
            while next <= displayPageCount && !isPagePairable(next) { next += 1 }

            guard next <= displayPageCount else { break }
            head = next
        }

        return min(head, displayPageCount)
    }

    private func canToggleOffset() -> Bool {
        guard
            usesDoublePages,
            displayPageCount > 1,
            chapter != nil,
            let visible = pageViewController.viewControllers,
            let idx = canonicalControllers(in: visible).compactMap({ pageViewControllers.firstIndex(of: $0) }).min()
        else { return false }
        let page = pageIndex(from: idx)
        return page >= 1 && page <= displayPageCount
    }

    private func isPageIsolated(_ displayPage: Int) -> Bool {
#if SUMI
        if displayPage == 1, sumiHasOpeningIndex || previousChapter != nil { return true }
#endif
        return isolatedPages.contains(displayPage)
    }

    private func setPageIsolated(_ page: Int, isolated: Bool, isManual: Bool = false) {
        if isolated {
            isolatedPages.insert(page)
            if isManual { manuallyIsolatedPages.insert(page) }
        } else {
            isolatedPages.remove(page)
            if isManual { manuallyIsolatedPages.remove(page) }
        }
    }

    private func resetIsolation() {
        isolatedPages = []
        manuallyIsolatedPages = []

        if pageOffsetEnabled {
            let head = splitWideImages ? 1 : firstToggleableHead()
            isolatedPages.insert(head > 0 ? head : 1)
        }
    }

    private func adjustAutoIsolation() {
        guard pageOffsetEnabled else { return }
        let autoIsolated = isolatedPages.subtracting(manuallyIsolatedPages)
        let newHead = firstToggleableHead()
        let desired: Set<Int> = newHead > 0 ? [newHead] : []
        guard autoIsolated != desired else { return }
        isolatedPages = manuallyIsolatedPages.union(desired)
    }
}

// MARK: - Reader Delegate
extension ReaderPagedViewController: ReaderReaderDelegate {
    private func moveBookGroup(physicalForward: Bool) -> Bool {
        guard displayingBookLayout, let current = pageViewController.viewControllers?.first,
              let group = bookGroup(for: current), let plan = bookPlan else { return false }
        let logicalForward = physicalForward != (readingMode == .rtl)
#if SUMI
        if sumiHasOpeningIndex, !logicalForward,
           group == plan.groupIndex(containingCanonicalIndex: sumiFirstCanonicalIndex) { return true }
#endif
        let next = group + (logicalForward ? 1 : -1)
        guard plan.groups.indices.contains(next) else { return true }
        let targets = bookPresentation(group: next, transition: desiredTransition)
        let previous = pageViewController.viewControllers ?? []
        isTransitioning = true
        programmaticMove = false
        if UserDefaults.standard.bool(forKey: "Reader.animatePageTransitions") { freezePagerViewport() }
        updateBookSpine()
        prepareForPresentation(targets)
        #if SUMI
        let animationForward = usesCanonicalSlideDirection(pageViewController) ? logicalForward : physicalForward
        #else
        let animationForward = physicalForward
        #endif
        let activePager = pageViewController
        pageViewController.setViewControllers(targets, direction: animationForward ? .forward : .reverse,
            animated: UserDefaults.standard.bool(forKey: "Reader.animatePageTransitions")) { [weak self, weak activePager] completed in
            guard let self, let activePager else { return }
            self.pageViewController(activePager, didFinishAnimating: true,
                previousViewControllers: previous, transitionCompleted: completed)
        }
        disableNativeCurlTaps()
        return true
    }

    func moveLeft() { movePhysical(forward: false) }
    func moveRight() { movePhysical(forward: true) }

    private func movePhysical(forward: Bool) {
        guard !isTransitioning else { return }
        updatePageTransitionIfNeeded()
        if moveBookGroup(physicalForward: forward) { return }
        guard let current = pageViewController.viewControllers?.first else { return }
        #if SUMI
        // Toolbar and key commands retain Aidoku's source-aware moveLeft/Right
        // interface. The native sliding surface always advances leftward.
        let navigationForward = usesCanonicalSlideDirection(pageViewController) && readingMode == .rtl ? !forward : forward
        #else
        let navigationForward = forward
        #endif
        let target = navigationForward ? pageViewController(pageViewController, viewControllerAfter: current)
            : pageViewController(pageViewController, viewControllerBefore: current)
        guard let target else { return }
        let previous = pageViewController.viewControllers ?? []
        isTransitioning = true
        programmaticMove = false
        if UserDefaults.standard.bool(forKey: "Reader.animatePageTransitions") { freezePagerViewport() }
        prepareForPresentation([target])
        let activePager = pageViewController
        pageViewController.setViewControllers([target], direction: navigationForward ? .forward : .reverse,
            animated: UserDefaults.standard.bool(forKey: "Reader.animatePageTransitions")) { [weak self, weak activePager] completed in
            guard let self, let activePager else { return }
            self.pageViewController(activePager, didFinishAnimating: true,
                previousViewControllers: previous, transitionCompleted: completed)
        }
        disableNativeCurlTaps()
    }

    func sliderMoved(value: CGFloat) {
        let displayPage = Int(round(value * CGFloat(displayPageCount - 1))) + 1
        let actualPage = actualPageIndex(from: displayPage)
        delegate?.displayPage(actualPage)
    }

    func sliderStopped(value: CGFloat) {
        let displayPage = Int(round(value * CGFloat(displayPageCount - 1))) + 1
        move(toPage: displayPage, animated: false)
    }

    func setChapter(_ chapter: AidokuRunner.Chapter, startPage: Int) {
        setChapter(chapter, startPage: startPage, showLoading: true)
    }

    private func setChapter(_ chapter: AidokuRunner.Chapter, startPage: Int, showLoading: Bool) {
        let isChapterChange = self.chapter?.id != chapter.id
        if isChapterChange {
            #if SUMI
            sumiCanonicalFocus = nil
            sumiQueuedCanonicalFocus = nil
            sumiPreparedNextChapterID = nil
            sumiNextChapterRetryAfter = .distantPast
            viewModel.sumiCancelPreload(except: chapter)
            #endif
            nextChapterPreloadTask?.cancel()
            if chapter != nextChapter {
                pagePrefetcher.reset()
            }
        }
        self.chapter = chapter
        #if SUMI
        sumiStopAnimatedNavigation()
        // A prefetched boundary already presents the next cover. Do not cover
        // that paper with a loading screen while its page graph is handed off.
        if showLoading { sumiChapterState().showLoading() }
        #endif
        Task {
            await loadChapter(startPage: startPage, isChapterChange: isChapterChange)
        }
    }

    func loadChapter(startPage: Int, isChapterChange: Bool = true) async {
        guard let chapter else { return }
        #if SUMI
        let committed = await viewModel.loadPages(chapter: chapter)
        guard committed, self.chapter?.key == chapter.key else { return }
        #else
        await viewModel.loadPages(chapter: chapter)
        #endif
        delegate?.setPages(viewModel.pages)
        #if SUMI
        if viewModel.pages.isEmpty {
            sumiChapterState().showError { [weak self] in self?.setChapter(chapter, startPage: startPage) }
            return
        }
        #endif
        if !viewModel.pages.isEmpty {
            await MainActor.run {
                if !isChapterChange, let key = splitPageCacheKey {
                    Self.splitStore[key] = nil
                }
                splitPages = [:]

                updatePageLayout()
                loadPageControllers(chapter: chapter)

                if isChapterChange {
                    resetIsolation()
                }

                let clampedStart = max(startPage, 1)
                let targetPage: Int
                if
                    splitWideImages,
                    let key = splitPageCacheKey,
                    let pos = savedSplitPosition(for: key),
                    pos.page == clampedStart,
                    splitPages[pos.page] != nil
                {
                    let first = firstDisplayPage(forActual: pos.page)
                    let last = lastDisplayPage(forActual: pos.page)
                    targetPage = min(first + pos.offset, last)
                } else {
                    targetPage = firstDisplayPage(forActual: clampedStart)
                }
#if SUMI
                if sumiHasOpeningIndex, !sumiDidPresentOpening {
                    sumiDidPresentOpening = true
                    sumiCanonicalFocus = nil
                    move(toPage: usesBookLayout ? 1 : 0, animated: false)
                } else {
                    sumiCanonicalFocus = (chapter.id, min(clampedStart, viewModel.pages.count))
                    move(toPage: max(1, min(targetPage, displayPageCount)), animated: false)
                }
#else
                move(toPage: max(1, min(targetPage, displayPageCount)), animated: false)
#endif
                #if SUMI
                sumiHideChapterState()
                #endif
            }
        }
    }

    func refreshChapter(startPage: Int) {
        guard let chapter else { return }

        loadPageControllers(chapter: chapter)
        move(toPage: max(1, min(startPage, displayPageCount)), animated: false)
    }

    func loadPreviousChapter() {
        guard let previousChapter else { return }
        nextPreviewSplitPages = splitPages[1]
        delegate?.setChapter(previousChapter)
        setChapter(previousChapter, startPage: Int.max)
    }

    func loadNextChapter(keepingBoundaryVisible: Bool = false) {
        guard let nextChapter else { return }
        previousPreviewSplitPages = splitPages[viewModel.pages.count]
        delegate?.setChapter(nextChapter)
        setChapter(nextChapter, startPage: 1, showLoading: !keepingBoundaryVisible)
    }
}

// MARK: - Page Controller Delegate
extension ReaderPagedViewController: UIPageViewControllerDelegate {

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        #if SUMI
        // A discarded pre-rotation pager cannot report against the replacement.
        guard pageViewController === self.pageViewController else { return }
        isTransitioning = sumiSequenceIsActive
        #else
        isTransitioning = false
        #endif
        #if SUMI
        // A requested second leaf remains the bookmark through layout changes
        // and cancelled turns. A completed real turn establishes a new spread.
        if completed, !programmaticMove { sumiCanonicalFocus = nil }
        #endif
        updateBookSpine()
        setLiveTextButtonHidden(delegate?.barsHidden ?? false)
        defer {
            if transitionPagerFrame != nil || pendingPageMove != nil || pendingSpreadRebuild || pendingPageTransitionRebuild {
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isTransitioning else { return }
                    if let requested = self.pendingPageMove {
                        self.pendingPageMove = nil
                        #if SUMI
                        let queuedFocus = self.sumiQueuedCanonicalFocus
                        self.sumiQueuedCanonicalFocus = nil
                        #endif
                        // A delayed slider jump belongs to the chapter in which
                        // it was requested, never a newly loaded adjacent chapter.
                        if requested.chapterID == self.chapter?.id {
                            #if SUMI
                            if let queuedFocus, queuedFocus.chapterID == self.chapter?.id,
                               self.actualPageIndex(from: requested.page) == queuedFocus.page {
                                self.sumiCanonicalFocus = queuedFocus
                            }
                            #endif
                            self.pendingSpreadRebuild = false
                            self.settlePagerViewport()
                            self.move(toPage: requested.page, animated: requested.animated, resetGesture: requested.resetGesture)
                            return
                        }
                    }
                    self.updatePageTransitionIfNeeded()
                    if self.pendingSpreadRebuild, !self.pageViewControllers.isEmpty {
                        self.pendingSpreadRebuild = false
                        if !self.visiblePresentationMatchesCurrentLayout() {
                            self.move(toPage: self.currentPage, animated: false, resetGesture: false)
                        }
                    }
                    if !self.isTransitioning { self.settlePagerViewport() }
                }
            }
        }
        if completed {
            for controller in leafControllers(in: previousViewControllers) {
                if let wide = controller as? ReaderBookWideLeafViewController { wide.clearLiveTextSelection() }
            }
            for page in canonicalControllers(in: previousViewControllers) { page.pageView?.clearLiveTextSelection() }
        }
#if SUMI
        if completed, pageViewController.viewControllers?.first is SumiIndexLeafViewController {
            currentPage = 0
            programmaticMove = false
            (delegate as? ReaderViewController)?.sumiDidShowIndex()
            loadPages(in: 1...max(1, pagesToPreload))
            return
        }
#endif
        guard completed, let visible = pageViewController.viewControllers,
              let currentIndex = canonicalControllers(in: visible).compactMap({ pageViewControllers.firstIndex(of: $0) }).min()
        else { programmaticMove = false; return }
        var page = currentIndex + (previousChapter != nil ? -1 : 0)
#if SUMI
        // The left leaf is the previous chapter's end, while the selected
        // artwork on the right is this chapter's real first page.
        if displayingBookLayout, page == 0,
           canonicalControllers(in: visible).contains(where: { $0 === pageViewControllers[safe: 2] }) {
            page = 1
        }
        currentPage = page
#else
        if displayingBookLayout || !programmaticMove { currentPage = page }
#endif
        programmaticMove = false
        switch page {
            case -1: // previous chapter last page
                pendingSpreadRebuild = false
                // move previous
                loadPreviousChapter()

            case 0: // previous chapter transition page
                delegate?.setCurrentPage(0, position: nil)
                // preload previous
                if let previousChapter = previousChapter {
                    Task {
                        await viewModel.preload(chapter: previousChapter)
                        if currentIndex > 0, let lastPage = viewModel.preloadedPages.last {
                            pageViewControllers[currentIndex - 1].setPage(
                                lastPage,
                                sourceId: viewModel.source?.key ?? viewModel.manga.sourceKey
                            )
                        }
                    }
                }

            case displayPageCount + 1: // next chapter transition page
                delegate?.setCurrentPage(displayPageCount + 1, position: nil)
                // preload next
                preloadNextChapter(pageCount: pagesToPreload)
                #if SUMI
                if displayingBookLayout, nextChapter != nil {
                    loadNextChapter(keepingBoundaryVisible: true)
                }
                #endif

            case displayPageCount + 2: // next chapter first page
                pendingSpreadRebuild = false
                // move next
                loadNextChapter()

            default:
                let actualPage = actualPageIndex(from: currentPage)
                if let key = splitPageCacheKey {
                    saveSplitPosition(for: key, page: actualPage, offset: splitIndex(for: currentPage, actualPageIndex: actualPage))
                }
                if let range = visibleActualPageRange(in: visible) {
                    #if SUMI
                    if let focus = sumiCanonicalFocus, focus.chapterID == chapter?.id,
                       range.contains(focus.page) {
                        delegate?.setCurrentPage(focus.page, position: nil)
                    } else {
                        sumiCanonicalFocus = nil
                        if range.lowerBound == range.upperBound {
                            delegate?.setCurrentPage(range.lowerBound, position: nil)
                        } else {
                            delegate?.setCurrentPages(range)
                        }
                    }
                    #else
                    if range.lowerBound == range.upperBound {
                        delegate?.setCurrentPage(range.lowerBound, position: nil)
                    } else {
                        delegate?.setCurrentPages(range)
                    }
                    #endif
                }
                #if SUMI
                sumiPreloadNeighborhood(around: page, discardDistantPages: true)
                #else
                // preload 1 before and pagesToPreload ahead
                loadPages(in: page - 1 - (usesDoublePages ? 1 : 0)...page + pagesToPreload + (usesDoublePages ? 1 : 0))
                #endif

                if
                    usesDoublePages,
                    let doubleVC = pageViewController.viewControllers?.first as? ReaderDoublePageViewController
                {
                    let first = doubleVC.firstPageController
                    let second = doubleVC.secondPageController
                    if
                        !pageViewControllers.contains(first) || !pageViewControllers.contains(second),
                        let idx = pageViewControllers.firstIndex(of: first)
                            ?? pageViewControllers.firstIndex(of: second)
                    {
                        pendingSpreadRebuild = false
                        move(toPage: pageIndex(from: idx), animated: false, resetGesture: false)
                    } else if
                        !splitWideImages,
                        first.isWideImage || second.isWideImage
                    {
                        pendingSpreadRebuild = false
                        move(toPage: page, animated: false, resetGesture: true)
                    }
                }
        }
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
    ) {
        #if SUMI
        guard pageViewController === self.pageViewController else { return }
        sumiCancelAnimatedNavigation()
        guard pageViewController === self.pageViewController else { return }
        #endif
        isTransitioning = true
        freezePagerViewport()
        updateBookSpine()
        setLiveTextButtonHidden(true)

        #if SUMI
        sumiOnPageTurnBegan?()
        #else
        if UserDefaults.standard.bool(forKey: "Reader.hideBarsOnSwipe") {
            delegate?.hideBars()
        }
        #endif

        for controller in pendingViewControllers {
            guard let idx = getIndex(of: controller, pos: .first) else { continue }
            let page = pageIndex(from: idx)
            #if SUMI
            sumiPreloadNeighborhood(around: page, discardDistantPages: false)
            #else
            if usesDoublePages {
                // include adjacent spreads so wide-image state is resolved for the next data source query
                loadPages(in: page - 2...page + 3)
            } else {
                loadPage(at: page)
            }
            #endif
        }
    }
}

// MARK: - Page Controller Data Source
extension ReaderPagedViewController: UIPageViewControllerDataSource {

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        if pageViewController.spineLocation == .mid {
            guard let slot = bookSlot(for: viewController) else { return nil }
            return bookPlan?.adjacentSlot(to: slot, after: true, readingMode: readingMode).map { bookController(for: $0) }
        }
        #if SUMI
        if usesCanonicalSlideDirection(pageViewController) { return getPageController(after: viewController) }
        #endif
        switch readingMode {
            case .rtl:
                return getPageController(before: viewController)
            case .ltr, .vertical:
                return getPageController(after: viewController)
            default:
                return nil
        }
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        if pageViewController.spineLocation == .mid {
            guard let slot = bookSlot(for: viewController) else { return nil }
            return bookPlan?.adjacentSlot(to: slot, after: false, readingMode: readingMode).map { bookController(for: $0) }
        }
        #if SUMI
        if usesCanonicalSlideDirection(pageViewController) { return getPageController(before: viewController) }
        #endif
        switch readingMode {
            case .rtl:
                return getPageController(after: viewController)
            case .ltr, .vertical:
                return getPageController(before: viewController)
            default:
                return nil
        }
    }

    func getPageController(after viewController: UIViewController) -> UIViewController? {
#if SUMI
        if sumiHasOpeningIndex, viewController is SumiIndexLeafViewController {
            return pageViewControllers[safe: sumiFirstCanonicalIndex].map { sumiStandalone($0) }
        }
#endif
        if displayingBookLayout, let group = bookGroup(for: viewController), let bookPlan {
            guard bookPlan.groups.indices.contains(group + 1) else { return nil }
            return bookPresentation(group: group + 1, transition: displayedTransition).first
        }
        guard let currentIndex = getIndex(of: viewController, pos: .second) else {
            return nil
        }
        if currentIndex + 1 < pageViewControllers.count {
            if usesDoublePages && currentIndex + 2 < pageViewControllers.count {
                let firstPage = pageViewControllers[currentIndex + 1]
                let secondPage = pageViewControllers[currentIndex + 2]
                if case .page = firstPage.type, case .page = secondPage.type {
                    let page = pageIndex(from: currentIndex + 1)
                    if
                        spreadStart(for: page) == page,
                        let double = createPageController(firstPage: firstPage, secondPage: secondPage, page: page)
                    {
                        return double
                    }
                }
            }
            #if SUMI
            return sumiStandalone(pageViewControllers[currentIndex + 1])
            #else
            return pageViewControllers[currentIndex + 1]
            #endif
        }
        return nil
    }

    func getPageController(before viewController: UIViewController) -> UIViewController? {
#if SUMI
        if sumiHasOpeningIndex {
            if viewController is SumiIndexLeafViewController { return nil }
            if displayingBookLayout, let group = bookGroup(for: viewController),
               group == bookPlan?.groupIndex(containingCanonicalIndex: sumiFirstCanonicalIndex) { return nil }
            if !displayingBookLayout, getIndex(of: viewController, pos: .first) == sumiFirstCanonicalIndex {
                return sumiIndexController().map { sumiStandalone($0) }
            }
        }
#endif
        if displayingBookLayout, let group = bookGroup(for: viewController), let bookPlan {
            guard bookPlan.groups.indices.contains(group - 1) else { return nil }
            return bookPresentation(group: group - 1, transition: displayedTransition).first
        }
        guard let currentIndex = getIndex(of: viewController, pos: .first) else {
            return nil
        }
        if currentIndex - 1 >= 0 {
            if usesDoublePages && currentIndex - 2 >= 0 {
                let firstPage = pageViewControllers[currentIndex - 2]
                let secondPage = pageViewControllers[currentIndex - 1]
                if case .page = firstPage.type, case .page = secondPage.type {
                    let page = pageIndex(from: currentIndex - 2)
                    if
                        spreadStart(for: page) == page,
                        let double = createPageController(firstPage: firstPage, secondPage: secondPage, page: page)
                    {
                        return double
                    }
                }
            }
            #if SUMI
            return sumiStandalone(pageViewControllers[currentIndex - 1])
            #else
            return pageViewControllers[currentIndex - 1]
            #endif
        }
        return nil
    }
}

// MARK: - Dictionary Lookup
@available(iOS 18.0, *)
extension ReaderPagedViewController: @MainActor ReaderDictionaryReader {
    func recognizedText(at point: CGPoint) -> TextRecognizer.Result? {
        for controller in leafControllers(in: pageViewController.viewControllers ?? []) {
            let surfaces: [(ReaderPageViewController, UIImageView, UIView)]
            if let wide = controller as? ReaderBookWideLeafViewController {
                surfaces = [(wide.canonicalController, wide.imageView, wide.view)]
            } else {
                surfaces = canonicalControllers(in: [controller]).compactMap { page in
                    page.pageView.map { (page, $0.imageView, controller.view) }
                }
            }
            for (page, imageView, clipView) in surfaces {
                guard clipView.bounds.contains(view.convert(point, to: clipView)),
                      let image = imageView.image, let recognizer = page.pageView?.textRecognizer else { continue }
                let localPoint = view.convert(point, to: imageView)
                guard imageView.bounds.contains(localPoint) else { continue }
                if var result = recognizer.findText(at: localPoint, in: imageView, imageSize: image.size) {
                    let clip = clipView.convert(clipView.bounds, to: view)
                    result.charRect = clipped(imageView.convert(result.charRect, to: view), to: clip)
                    result.charRects = result.charRects.map { clipped(imageView.convert($0, to: view), to: clip) }
                    return result
                }
            }
        }
        return nil
    }

    private func clipped(_ rect: CGRect, to clip: CGRect) -> CGRect {
        let result = rect.intersection(clip)
        return result.isNull ? .zero : result
    }

    private func visiblePageControllers() -> [ReaderPageViewController] {
        canonicalControllers(in: pageViewController.viewControllers ?? [])
    }

    func setDictionaryOverlayTapHandler(_ handler: ((String, String, CGRect, [CGRect]) -> Void)?) {
        dictionaryOverlayTapHandler = handler
        for controller in pageViewControllers { bindDictionaryOverlayTap(to: controller) }
        for case let wide as ReaderBookWideLeafViewController in bookControllers.values { bindDictionaryOverlayTap(to: wide) }
    }

    func setDictionaryOverlayInteractionMode(_ mode: DictionaryOverlayInteractionMode) {
        dictionaryOverlayInteractionMode = mode
        for controller in pageViewControllers {
            controller.pageView?.setDictionaryOverlayInteractionMode(mode)
        }
        for case let wide as ReaderBookWideLeafViewController in bookControllers.values { wide.dictionaryInteractionMode = mode }
    }

    func dismissActiveDictionaryOverlay() -> Bool {
        for case let wide as ReaderBookWideLeafViewController in leafControllers(in: pageViewController.viewControllers ?? [])
            where wide.dismissActiveDictionaryOverlay() { return true }
        for pageVC in visiblePageControllers() where pageVC.pageView?.dismissActiveDictionaryOverlay() == true {
            return true
        }
        return false
    }

    private func forwardDictionaryOverlayTap(
        text: String,
        contextText: String,
        rect: CGRect,
        charRects: [CGRect],
        from imageView: UIImageView
    ) {
        let rectInReader = imageView.convert(rect, to: view)
        let charRectsInReader = charRects.map { imageView.convert($0, to: view) }
        dictionaryOverlayTapHandler?(text, contextText, rectInReader, charRectsInReader)
    }

    private func bindDictionaryOverlayTap(to wide: ReaderBookWideLeafViewController) {
        wide.dictionaryInteractionMode = dictionaryOverlayInteractionMode
        wide.onDictionaryLookup = { [weak self, weak wide] text, context, rect, charRects in
            guard let self, let wide else { return }
            let clip = wide.view.convert(wide.view.bounds, to: self.view)
            let anchor = self.clipped(wide.imageView.convert(rect, to: self.view), to: clip)
            let characters = charRects.map { self.clipped(wide.imageView.convert($0, to: self.view), to: clip) }
            self.dictionaryOverlayTapHandler?(text, context, anchor, characters)
        }
    }

    private func bindDictionaryOverlayTap(to controller: ReaderPageViewController?) {
        controller?.pageView?.setDictionaryOverlayInteractionMode(dictionaryOverlayInteractionMode)
        controller?.pageView?.onDictionaryOverlayTap = { [weak self, weak controller] text, contextText, rect, charRects in
            guard let self, let imageView = controller?.pageView?.imageView else { return }
            self.forwardDictionaryOverlayTap(text: text, contextText: contextText, rect: rect, charRects: charRects, from: imageView)
        }
    }
}

// MARK: - Context Menu Delegate
extension ReaderPagedViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard
            let pageView = interaction.view as? UIImageView,
            pageView.image != nil,
            !AppSettings.dictionary.isReaderQuickActionsDisabled(language: pageLanguage(for: pageView))
        else {
            return nil
        }
        // disable when live text highlighting is active
        if
            #available(iOS 16.0, *),
            let imageAnalaysisInteraction = pageView.interactions.first as? ImageAnalysisInteraction,
            imageAnalaysisInteraction.selectableItemsHighlighted
        {
            return nil
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
            let shareAction = UIAction(
                title: NSLocalizedString("SHARE"),
                image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                if let image = pageView.image {
                    let items = [image]
                    let activityController = UIActivityViewController(activityItems: items, applicationActivities: nil)

                    activityController.popoverPresentationController?.sourceView = self.view
                    activityController.popoverPresentationController?.sourceRect = CGRect(
                        origin: pageView.convert(location, to: self.view), size: .zero
                    )

                    self.present(activityController, animated: true)
                }
            }

            let saveToPhotosAction = UIAction(
                title: NSLocalizedString("SAVE_TO_PHOTOS"),
                image: UIImage(systemName: "square.and.arrow.down")
            ) { _ in
                if let image = pageView.image {
                    image.saveToAlbum(viewController: self)
                }
            }

            let reloadAction = UIAction(
                title: NSLocalizedString("RELOAD"),
                image: UIImage(systemName: "arrow.clockwise")
            ) { _ in
                Task { @MainActor in
                    await self.reloadCurrentPageImage(for: pageView)
                }
            }

            var actions = [shareAction, saveToPhotosAction, reloadAction]

            if self.usesDoublePages {
                for (index, pageViewController) in self.pageViewControllers.enumerated() {
                    guard
                        case .page = pageViewController.type,
                        self.canonicalController(for: pageView) === pageViewController
                    else { continue }

                    let page = self.pageIndex(from: index)
                    let isManuallySet = self.manuallyIsolatedPages.contains(page)
                    if isManuallySet {
                        let unsetAction = UIAction(
                            title: NSLocalizedString("UNSET_AS_SINGLE_PAGE"),
                            image: UIImage(systemName: "rectangle.portrait.slash")
                        ) { _ in
                            Task { @MainActor in
                                self.setManualIsolation(for: pageView, isolated: false)
                            }
                        }
                        actions.insert(unsetAction, at: 2)
                    } else if self.canDisplayAsDoublePage(page) {
                        let setAction = UIAction(
                            title: NSLocalizedString("SET_AS_SINGLE_PAGE"),
                            image: UIImage(systemName: "rectangle.portrait")
                        ) { _ in
                            Task { @MainActor in
                                self.setManualIsolation(for: pageView, isolated: true)
                            }
                        }
                        actions.insert(setAction, at: 2)
                    }

                    break
                }
            }

            return UIMenu(title: "", children: actions)
        })
    }

    @MainActor
    private func reloadCurrentPageImage(for imageView: UIImageView) async {
        for pageViewController in pageViewControllers {
            if
                case .page = pageViewController.type,
                let readerPageView = pageViewController.pageView,
                canonicalController(for: imageView) === pageViewController
            {
                let success = await readerPageView.reloadCurrentImage()
                if !success {
                    showReloadError()
                }
                return
            }
        }
    }

    @MainActor
    private func setManualIsolation(for imageView: UIImageView, isolated: Bool) {
        for (index, pageViewController) in pageViewControllers.enumerated() {
            if
                case .page = pageViewController.type,
                canonicalController(for: imageView) === pageViewController
            {
                let page = pageIndex(from: index)
                if !isolated {
                    let orphan = page + 1
                    if isolatedPages.contains(orphan), !manuallyIsolatedPages.contains(orphan) {
                        isolatedPages.remove(orphan)
                    }
                }
                setPageIsolated(page, isolated: isolated, isManual: true)
                refreshChapter(startPage: page)
                return
            }
        }
    }

    private func showReloadError() {
        let alert = UIAlertController(
            title: NSLocalizedString("RELOAD_FAILED"),
            message: NSLocalizedString("RELOAD_FAILED_TEXT"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK"), style: .default))
        present(alert, animated: true)
    }

    private func canonicalController(for imageView: UIImageView) -> ReaderPageViewController? {
        if let canonical = pageViewControllers.first(where: { $0.pageView?.imageView === imageView }) { return canonical }
        return bookControllers.values.compactMap { $0 as? ReaderBookWideLeafViewController }
            .first(where: { $0.imageView === imageView })?.canonicalController
    }

    private func pageLanguage(for imageView: UIImageView) -> String? {
        canonicalController(for: imageView)?.page?.language
    }

}

// MARK: - Split Page Store
extension ReaderPagedViewController {
    private static var splitStore: [String: [Int: [Page]]] = [:]
    private static var splitPosition: [String: (page: Int, offset: Int)] = [:]

    private static func clearSplitPageCache() {
        splitStore.removeAll()
        splitPosition.removeAll()
    }

    private var splitPageCacheKey: String? {
        guard let chapterId = chapter?.id else { return nil }
        return "\(viewModel.manga.identifier)/\(chapterId)"
    }

    private func reverseSplitStoreEntries(for key: String) {
        guard let cached = Self.splitStore[key] else { return }
        Self.splitStore[key] = cached.mapValues { $0.reversed() }
    }

    private func hasCachedSplit(_ actualPage: Int) -> Bool {
        guard let key = splitPageCacheKey else { return false }
        return Self.splitStore[key]?[actualPage] != nil
    }

    private func cacheSplitPages(_ pages: [Page], at pageIndex: Int) {
        guard let key = splitPageCacheKey, pageIndex >= 1, pageIndex <= viewModel.pages.count else { return }
        Self.splitStore[key, default: [:]][pageIndex] = pages
    }

    private func restoreCachedSplitPages() {
        guard
            let key = splitPageCacheKey,
            let cached = Self.splitStore[key]
        else { return }
        for (pageIndex, pages) in cached where splitPages[pageIndex] == nil {
            guard pages.allSatisfy({ $0.image != nil }) else { continue }
            splitPages[pageIndex] = pages
        }
    }

    private func savedSplitPosition(for key: String) -> (page: Int, offset: Int)? {
        Self.splitPosition[key]
    }

    private func saveSplitPosition(for key: String, page: Int, offset: Int) {
        Self.splitPosition[key] = (page, offset)
    }
}
