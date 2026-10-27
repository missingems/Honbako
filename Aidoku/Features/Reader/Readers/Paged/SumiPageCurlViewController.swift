#if SUMI
import UIKit

/// A scrubbed route has one clock, regardless of the number of leaves crossed.
/// Easing belongs to the complete route rather than restarting at each binding.
enum SumiPageCurlJourneyTimeline {
    static let duration: TimeInterval = 0.65

    static func easedProgress(_ progress: Double) -> Double {
        let time = min(1, max(0, progress))
        return time * time * (3 - 2 * time)
    }

    static func distance(at elapsed: TimeInterval, turns: Int) -> CGFloat {
        CGFloat(max(0, turns)) * CGFloat(easedProgress(elapsed / duration))
    }
}

/// The reader retains its normal data-source and delegate contract, while Sumi
/// owns the paper interaction and renderer. UIKit's scrolling/curling surfaces
/// are never used for a Sumi turn.
final class SumiPageCurlViewController: UIPageViewController, UIGestureRecognizerDelegate {
    private let content = UIView()
    let readingMode: ReadingMode
    private var displayedControllers: [UIViewController] = []
    private var pendingControllers: [UIViewController] = []
    private var turnView: SumiPageCurlView?
    private var progress: CGFloat = 0
    private var turnsRightToLeft = false
    private var interactive = false
    private var completionHandler: ((Bool) -> Void)?
    private var displayLink: CADisplayLink?
    private var animationWatchdog: Task<Void, Never>?
    private var animationIdentity = UUID()
    private var animationStart: CFTimeInterval = 0
    private var animationDuration: CFTimeInterval = 0
    private var animationFrom: CGFloat = 0
    private var animationTo: CGFloat = 0
    struct JourneyStep {
        let controllers: [UIViewController]
        let direction: NavigationDirection
    }
    private final class Journey {
        let steps: [JourneyStep]
        var artwork: [SumiPageCurlView.Artwork?]
        let surface: SumiPageCurlView
        let didCompleteStep: (Int, [UIViewController]) -> Void
        let completion: (Bool) -> Void
        var index = 0

        init(steps: [JourneyStep], artwork: [SumiPageCurlView.Artwork], surface: SumiPageCurlView,
             didCompleteStep: @escaping (Int, [UIViewController]) -> Void,
             completion: @escaping (Bool) -> Void) {
            self.steps = steps
            self.artwork = artwork.map(Optional.some)
            self.surface = surface
            self.didCompleteStep = didCompleteStep
            self.completion = completion
        }
    }
    private var journey: Journey?
    private let paperHaptics = SumiPaperHaptics(inputMode: "landscapeCurl")
    private var loadingTargetLeaves: [UIViewController] = []
    private var hasFingerLift = false
    private var lastDragTranslation: CGFloat = 0
    private var lastDragTime: CFTimeInterval = 0
    private lazy var curlPan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))

    var isTurning: Bool { turnView != nil || journey != nil }

    override var viewControllers: [UIViewController]? { displayedControllers.isEmpty ? nil : displayedControllers }
    override var gestureRecognizers: [UIGestureRecognizer] { [curlPan] }

    init(readingMode: ReadingMode = .rtl) {
        self.readingMode = readingMode
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "sumi.reader.curl"
        // UIPageViewController is used solely as a compatibility interface for
        // the existing reader model. Its native pager has no content or gestures.
        for child in view.subviews {
            child.isHidden = true
            child.isUserInteractionEnabled = false
        }
        content.frame = view.bounds
        content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        content.backgroundColor = SumiPaperSurface.backgroundColor
        view.addSubview(content)
        curlPan.delegate = self
        curlPan.maximumNumberOfTouches = 1
        curlPan.cancelsTouchesInView = true
        // A trackpad's horizontal two-finger scroll is the same direct paper
        // interaction as a finger drag; native vertical readers keep scrolling.
        curlPan.allowedScrollTypesMask = [.continuous, .discrete]
        view.addGestureRecognizer(curlPan)
        view.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: NSLocalizedString("Next page", comment: "")) { [weak self] _ in
                guard let self else { return false }
                return self.turn(forward: self.readingMode != .rtl)
            },
            UIAccessibilityCustomAction(name: NSLocalizedString("Previous page", comment: "")) { [weak self] _ in
                guard let self else { return false }
                return self.turn(forward: self.readingMode == .rtl)
            }
        ]
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let turnView, turnView.bounds.size != content.bounds.size {
            // The outer reader normally freezes its viewport. If a container
            // changes it directly, cancel against the still-current identity
            // instead of stretching captured paper or committing an unseen page.
            cancelCurrentTurn()
        }
        for controller in displayedControllers + pendingControllers {
            controller.view.frame = content.bounds
            controller.view.layoutIfNeeded()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        paperHaptics.suspend()
        cancelCurrentTurn()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        paperHaptics.prepare(in: view)
    }

    deinit { displayLink?.invalidate(); animationWatchdog?.cancel() }

    override func setViewControllers(_ viewControllers: [UIViewController]?, direction: NavigationDirection,
                                     animated: Bool, completion: ((Bool) -> Void)? = nil) {
        loadViewIfNeeded()
        let targets = viewControllers ?? []
        guard !targets.isEmpty else { completion?(false); return }
        guard turnView == nil else { completion?(false); return }
        if !animated || displayedControllers.isEmpty || targets.elementsEqual(displayedControllers, by: { $0 === $1 }) {
            replace(with: targets)
            completion?(true)
            return
        }
        completionHandler = completion
        interactive = false
        begin(targets: targets, rightToLeft: rendersRightToLeft(navigationForward: direction == .forward))
        animate(to: 1, velocity: 0)
    }

    /// Capture every actual surface before the animation clock starts. The
    /// timed path only deforms prepared leaves; it never waits on image loading,
    /// renders a new snapshot, or restarts easing at a page boundary.
    func animateJourney(through steps: [JourneyStep], began: () -> Void,
                        didCompleteStep: @escaping (Int, [UIViewController]) -> Void,
                        completion: @escaping (Bool) -> Void) {
        loadViewIfNeeded()
        guard !isTurning, !displayedControllers.isEmpty, !steps.isEmpty else { completion(false); return }
        // Bound transient print rasters over a long chapter. A distant leaf is
        // visible for fewer frames, while the final live page retains full detail.
        let area = max(1, content.bounds.width * content.bounds.height)
        let scale = min(max(1, traitCollection.displayScale),
                        max(0.01, sqrt(8_000_000 / (area * CGFloat(steps.count + 1)))))
        var prints = snapshots(of: displayedControllers, scale: scale)
        guard !prints.isEmpty else { completion(false); return }
        var artwork: [SumiPageCurlView.Artwork] = []
        for step in steps {
            for controller in step.controllers { stageForSnapshot(controller) }
            let next = snapshots(of: step.controllers, scale: scale)
            for controller in step.controllers where !displayedControllers.contains(where: { $0 === controller }) {
                controller.remove()
            }
            guard !next.isEmpty else { completion(false); return }
            artwork.append(SumiPageCurlView.prepareArtwork(oldImages: prints, newImages: next,
                rightToLeft: rendersRightToLeft(navigationForward: step.direction == .forward)))
            prints = next
        }
        guard let firstArtwork = artwork.first else { completion(false); return }
        let surface = SumiPageCurlView(frame: content.bounds, artwork: firstArtwork)
        let route = Journey(steps: steps, artwork: artwork, surface: surface,
                            didCompleteStep: didCompleteStep, completion: completion)
        journey = route
        interactive = false
        beginJourneyStep(route)
        animationStart = CACurrentMediaTime()
        startDisplayLink()
        began()
    }

    /// Cancellation restores the last complete native page, never a half-turned bitmap.
    func cancelCurrentTurn() {
        paperHaptics.cancel()
        if let journey { finishJourney(journey, completed: false) }
        else if turnView != nil { finish(completed: false) }
    }

    private func beginJourneyStep(_ route: Journey) {
        guard journey === route, route.steps.indices.contains(route.index),
              let artwork = route.artwork[route.index], route.surface.replaceArtwork(artwork) else { return }
        let surface = route.surface
        pendingControllers = route.steps[route.index].controllers
        for controller in pendingControllers { mount(controller) }
        turnView = surface
        progress = 0
        surface.update(progress: 0)
        content.addSubview(surface)
        for controller in displayedControllers + pendingControllers { controller.view.isHidden = true }
    }

    private func tickJourney(_ route: Journey, timestamp: CFTimeInterval) {
        let elapsed = max(0, timestamp - animationStart)
        let distance = SumiPageCurlJourneyTimeline.distance(at: elapsed, turns: route.steps.count)
        let completedTurns = min(route.steps.count, Int(distance))
        while route.index < completedTurns, journey === route {
            turnView?.update(progress: 1)
            let previous = displayedControllers
            replace(with: pendingControllers)
            pendingControllers = []
            turnView?.removeFromSuperview()
            turnView = nil
            route.artwork[route.index] = nil
            let completedIndex = route.index
            route.index += 1
            route.didCompleteStep(completedIndex, previous)
            guard journey === route else { return }
            if route.index < route.steps.count { beginJourneyStep(route) }
        }
        guard journey === route else { return }
        if route.index == route.steps.count {
            finishJourney(route, completed: true)
        } else {
            progress = distance - CGFloat(route.index)
            turnView?.update(progress: progress)
        }
    }

    private func finishJourney(_ route: Journey, completed: Bool) {
        guard journey === route else { return }
        journey = nil
        stopDisplayLink()
        for controller in pendingControllers where !displayedControllers.contains(where: { $0 === controller }) { controller.remove() }
        pendingControllers = []
        turnView?.removeFromSuperview()
        turnView = nil
        for controller in displayedControllers { controller.view.isHidden = false }
        route.completion(completed)
    }

    private func replace(with targets: [UIViewController]) {
        for controller in displayedControllers where !targets.contains(where: { $0 === controller }) { controller.remove() }
        displayedControllers = targets
        for controller in targets {
            mount(controller)
            controller.view.isHidden = false
        }
        for leaf in loadingTargetLeaves {
            if let page = leaf as? ReaderPageViewController { page.pageView?.sumiRevealAfterLoadingPlaceholder() }
            else if let wide = leaf as? ReaderBookWideLeafViewController { wide.sumiRevealAfterLoadingPlaceholder() }
        }
        loadingTargetLeaves = []
    }

    private func mount(_ controller: UIViewController) {
        if controller.parent !== self {
            controller.remove()
            addChild(controller)
            // Stage an incoming page behind the current print. A layout or
            // image callback during snapshot preparation must not expose the
            // next page for one frame before the curl surface is installed.
            content.insertSubview(controller.view, at: 0)
            controller.didMove(toParent: self)
        }
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.frame = content.bounds
        if let spread = controller as? ReaderBookSpreadViewController { spread.attachLeaves() }
        else if let page = controller as? ReaderPageViewController {
            page.bookBindingEdge = .none
            page.updatePaperShape()
        } else if let wide = controller as? ReaderBookWideLeafViewController {
            wide.bookBindingEdge = .none
            wide.updatePaperShape()
        }
        controller.view.layoutIfNeeded()
    }

    private func snapshots(of controllers: [UIViewController], scale: CGFloat? = nil) -> [UIImage] {
        guard let controller = controllers.first else { return [] }
        let leaves = (controller as? ReaderBookSpreadViewController)?.leaves ?? [controller]
        return leaves.enumerated().map { index, leaf in
            leaf.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale ?? max(1, traitCollection.displayScale)
            format.opaque = false
            return UIGraphicsImageRenderer(size: leaf.view.bounds.size, format: format).image { context in
                let edge: ReaderBookSpineView.BindingEdge = leaves.count == 2 ? (index == 0 ? .right : .left) : .none
                context.cgContext.addPath(ReaderBookSpineView.pagePath(in: leaf.view.bounds, bindingEdge: edge))
                context.cgContext.clip()
                leaf.view.layer.render(in: context.cgContext)
            }
        }
    }

    private func stageForSnapshot(_ controller: UIViewController) {
        mount(controller)
        if !displayedControllers.contains(where: { $0 === controller }) {
            content.insertSubview(controller.view, at: 0)
        }
        // A completed turn detaches its old controller while hidden. The same
        // cached page can be requested again on a reverse turn, so restore its
        // print before capturing, with the live current page still above it.
        controller.view.isHidden = false
        if let spread = controller as? ReaderBookSpreadViewController {
            for leaf in spread.leaves { leaf.view.isHidden = false }
        }
    }

    private func begin(targets: [UIViewController], rightToLeft: Bool) {
        let oldImages = snapshots(of: displayedControllers)
        pendingControllers = targets
        for controller in targets { stageForSnapshot(controller) }
        let newImages = snapshots(of: targets)
        guard !oldImages.isEmpty, !newImages.isEmpty else { finish(completed: false); return }
        loadingTargetLeaves = targets.flatMap { ($0 as? ReaderBookSpreadViewController)?.leaves ?? [$0] }.filter { leaf in
            if let page = leaf as? ReaderPageViewController { return page.pageView?.imageView.image == nil }
            if let wide = leaf as? ReaderBookWideLeafViewController { return wide.imageView.image == nil }
            return false
        }
        turnsRightToLeft = rightToLeft
        progress = 0
        let turn = SumiPageCurlView(frame: content.bounds, oldImages: oldImages,
                                    newImages: newImages, rightToLeft: rightToLeft)
        content.addSubview(turn)
        turnView = turn
        for controller in displayedControllers + pendingControllers { controller.view.isHidden = true }
    }

#if DEBUG
    /// Pauses the actual interactive transition for visual inspection. This is
    /// unavailable unless the dedicated, in-memory preview was requested.
    @discardableResult func debugHoldTurn(progress requestedProgress: CGFloat) -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("--sumi-curl-check"),
              requestedProgress.isFinite, displayLink == nil else { return false }
        if turnView == nil {
            guard let current = displayedControllers.first else { return false }
            let forward = readingMode != .rtl
            let target = forward ? dataSource?.pageViewController(self, viewControllerAfter: current)
                : dataSource?.pageViewController(self, viewControllerBefore: current)
            guard let target else { return false }
            interactive = true
            delegate?.pageViewController?(self, willTransitionTo: [target])
            begin(targets: [target], rightToLeft: rendersRightToLeft(navigationForward: forward))
        }
        guard turnView != nil else { return false }
        progress = min(1, max(0, requestedProgress))
        turnView?.update(progress: progress)
        return true
    }

    @discardableResult func debugSettleTurn(completed: Bool) -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("--sumi-curl-check"),
              turnView != nil else { return false }
        animate(to: completed ? 1 : 0, velocity: 0)
        return true
    }
#endif

    @discardableResult private func turn(forward: Bool) -> Bool {
        guard turnView == nil, let current = displayedControllers.first else { return false }
        let target = forward ? dataSource?.pageViewController(self, viewControllerAfter: current)
            : dataSource?.pageViewController(self, viewControllerBefore: current)
        guard let target else { return false }
        interactive = true
        delegate?.pageViewController?(self, willTransitionTo: [target])
        begin(targets: [target], rightToLeft: rendersRightToLeft(navigationForward: forward))
        animate(to: 1, velocity: 0)
        return true
    }

    private func rendersRightToLeft(navigationForward: Bool) -> Bool {
        // Source order controls which spread is next, not the physical gesture.
        // Advancing manga always takes the right leaf over to the left.
        navigationForward != (readingMode == .rtl)
    }

    @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
            case .began:
                guard turnView == nil, let current = displayedControllers.first else { return }
                let canonicalForward = recognizer.velocity(in: view).x < 0
                let forward = canonicalForward != (readingMode == .rtl)
                let target = forward ? dataSource?.pageViewController(self, viewControllerAfter: current)
                    : dataSource?.pageViewController(self, viewControllerBefore: current)
                guard let target else { return }
                interactive = true
                lastDragTranslation = recognizer.translation(in: view).x
                lastDragTime = CACurrentMediaTime()
                delegate?.pageViewController?(self, willTransitionTo: [target])
                begin(targets: [target], rightToLeft: rendersRightToLeft(navigationForward: forward))
                if turnView != nil {
                    hasFingerLift = true
                    paperHaptics.begin(distance: turnDistance, visible: view.window != nil, location: recognizer.location(in: view))
                }
            case .changed:
                guard turnView != nil, displayLink == nil else { return }
                let rawTranslation = recognizer.translation(in: view).x
                if abs(rawTranslation - lastDragTranslation) >= 0.5 {
                    lastDragTranslation = rawTranslation
                    lastDragTime = CACurrentMediaTime()
                }
                let distance = turnDistance
                let translation = rawTranslation * (turnsRightToLeft ? -1 : 1)
                progress = min(1, max(0, translation / distance))
                turnView?.update(progress: progress)
                paperHaptics.update(progress: progress, velocity: recognizer.velocity(in: view).x, location: recognizer.location(in: view))
            case .ended:
                guard turnView != nil else { return }
                // UIPanGestureRecognizer may retain its last velocity while a
                // finger holds still. A paused release is no longer a flick.
                let velocity = CACurrentMediaTime() - lastDragTime > 0.12 ? 0
                    : recognizer.velocity(in: view).x * (turnsRightToLeft ? -1 : 1)
                let committed = SumiPageTurnIntent.shouldComplete(progress: progress, velocity: velocity, distance: turnDistance)
                releaseFingerLift(velocity: velocity, cancelled: !committed)
                animate(to: committed ? 1 : 0, velocity: velocity)
            case .cancelled, .failed:
                releaseFingerLift(velocity: 0, cancelled: true)
                if turnView != nil { animate(to: 0, velocity: 0) }
            default: break
        }
    }

    private func releaseFingerLift(velocity: CGFloat, cancelled: Bool) {
        guard hasFingerLift else { return }
        hasFingerLift = false
        paperHaptics.release(velocity: velocity, cancelled: cancelled)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === curlPan, turnView == nil else { return false }
        let velocity = curlPan.velocity(in: view)
        guard abs(velocity.x) > abs(velocity.y) * 1.05 else { return false }
        var touched = content.hitTest(curlPan.location(in: content), with: nil)
        while let candidate = touched {
            if let zoom = candidate as? ZoomableScrollView,
               zoom.zoomScale > zoom.minimumZoomScale + 0.02 { return false }
            touched = candidate.superview
        }
        paperHaptics.prepare(in: view)
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // The page keeps any vertical interaction while horizontal gestures
        // belong to the same physical curl in portrait and landscape.
        otherGestureRecognizer is UIPanGestureRecognizer
    }

    private func animate(to target: CGFloat, velocity: CGFloat) {
        guard turnView != nil else { return }
        displayLink?.invalidate()
        animationStart = CACurrentMediaTime()
        animationFrom = progress
        animationTo = target
        let remaining = abs(target - progress)
        animationDuration = max(0.16, min(0.52, Double(remaining) * 0.48 - min(abs(Double(velocity)) / 18000, 0.12)))
        startDisplayLink()
    }

    private func startDisplayLink() {
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        let maximum = Float(view.window?.windowScene?.screen.maximumFramesPerSecond ?? 60)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
        link.add(to: .main, forMode: .common)
        displayLink = link
        // Completion is driven by the real display link, rather than a caller
        // guessing when a shared transition flag has settled. Still bound an
        // interrupted system display clock so an awaiting scrub can recover.
        animationWatchdog?.cancel()
        let identity = UUID()
        animationIdentity = identity
        animationWatchdog = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, animationIdentity == identity, displayLink != nil else { return }
            cancelCurrentTurn()
        }
    }

    private func stopDisplayLink() {
        animationIdentity = UUID()
        animationWatchdog?.cancel()
        animationWatchdog = nil
        displayLink?.invalidate()
        displayLink = nil
    }

    private var turnDistance: CGFloat {
        max(1, content.bounds.width * (displayedControllers.first is ReaderBookSpreadViewController ? 0.45 : 0.75))
    }

    @objc private func tick(_ link: CADisplayLink) {
        if let journey { tickJourney(journey, timestamp: link.timestamp); return }
        let time = min(1, max(0, (link.timestamp - animationStart) / animationDuration))
        let eased = SumiPageCurlJourneyTimeline.easedProgress(time)
        progress = animationFrom + (animationTo - animationFrom) * CGFloat(eased)
        turnView?.update(progress: progress)
        if time >= 1 { finish(completed: animationTo == 1) }
    }

    private func finish(completed: Bool) {
        stopDisplayLink()
        let previous = displayedControllers
        if completed { replace(with: pendingControllers) }
        else {
            for controller in pendingControllers where !displayedControllers.contains(where: { $0 === controller }) { controller.remove() }
            for controller in displayedControllers { controller.view.isHidden = false }
        }
        pendingControllers = []
        turnView?.removeFromSuperview()
        turnView = nil
        let completion = completionHandler
        completionHandler = nil
        if interactive {
            delegate?.pageViewController?(self, didFinishAnimating: true,
                                         previousViewControllers: previous, transitionCompleted: completed)
        } else { completion?(completed) }
        loadingTargetLeaves = []
        hasFingerLift = false
        interactive = false
    }
}
#endif
