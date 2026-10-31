#if SUMI
import UIKit

final class SumiBookTransition: NSObject, UIViewControllerTransitioningDelegate, UIViewControllerInteractiveTransitioning, UIGestureRecognizerDelegate {
    private let sourceFrameProvider: ((UIView) -> CGRect?)?
    private let gridSourceFrameProvider: ((UIView) -> CGRect?)?
    let coverImage: UIImage?
    let closedPose: SumiGridBookPose?
    private let liftedFrame: CGRect?
    private let liftedViewport: CGSize?
    let sourceView: () -> UIView?
    let readerSurface: () -> UIView?
    let paired: () -> Bool
    var sourceVisibility: (Bool) -> Void = { _ in }
    var revealSourceForHandoff: () -> Void = {}
    var chromeTransition: (Bool) -> Void = { _ in }
    var closingBegan: () -> Void = {}
    var openingCancellationBegan: () -> Void = {}
    var openingCancelled: () -> Void = {}
    private var animator: SumiBookOpeningAnimator?
    private weak var owner: SumiDirectReaderController?
    private(set) var edgeSwipe: UIScreenEdgePanGestureRecognizer?
    private(set) var pinch: UIPinchGestureRecognizer?
    private(set) var interactiveFraction: CGFloat = 0
    private var interactive = false
    private var pendingEnd: (Bool, CGFloat)?
    private var isPinching = false
    var closesAtCenter: Bool { isPinching }
    var prepareReturn: (() async -> Void)?
    private var gestureHostObserver: SumiBookGestureHostObserver?
    private let panSuspension = SumiBookPanSuspension()

    init(coverImage: UIImage?, closedPose: SumiGridBookPose? = nil, liftedFrame: CGRect? = nil, liftedViewport: CGSize? = nil, sourceFrameProvider: ((UIView) -> CGRect?)? = nil, gridSourceFrameProvider: ((UIView) -> CGRect?)? = nil, readerSurface: @escaping () -> UIView?, paired: @escaping () -> Bool, sourceView: @escaping () -> UIView?) {
        self.sourceFrameProvider = sourceFrameProvider
        self.gridSourceFrameProvider = gridSourceFrameProvider
        self.closedPose = closedPose; self.liftedFrame = liftedFrame; self.liftedViewport = liftedViewport
        self.coverImage = coverImage; self.readerSurface = readerSurface; self.paired = paired; self.sourceView = sourceView
    }

    func install(on owner: SumiDirectReaderController) {
        #if DEBUG
        SumiBookPinchDiagnostics.resetIfNeeded()
        #endif
        uninstall()
        self.owner = owner
        let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(backSwipe(_:)))
        gesture.edges = owner.view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        gesture.delegate = self
        (owner.readerViewController?.view ?? owner.view).addGestureRecognizer(gesture); edgeSwipe = gesture
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(closePinch(_:)))
        pinch.delegate = self
        // A genuine two-finger contraction also owns touches that began on a
        // reader button. Cancel its tracking instead of turning the release
        // into a Chapters tap; ordinary one-finger taps stay immediate.
        pinch.cancelsTouchesInView = true
        pinch.delaysTouchesBegan = false
        owner.view.addGestureRecognizer(pinch)
        self.pinch = pinch
        let observer = SumiBookGestureHostObserver(frame: .zero)
        observer.windowDidChange = { [weak self] in self?.updatePinchHost() }
        owner.view.addSubview(observer)
        gestureHostObserver = observer
        owner.interactivePopGestureRecognizer?.isEnabled = false
        if #available(iOS 26.0, *) { owner.interactiveContentPopGestureRecognizer?.isEnabled = false }
        prioritizeBackSwipe()
    }

    func prioritizeBackSwipe() {
        updatePinchHost()
        if let surface = readerSurface() { SumiReaderGesturePolicy.reservePinches(in: surface) }
        if isPinching, interactive { suspendReaderPans() }
        guard let edgeSwipe, let reader = owner?.readerViewController?.reader as? ReaderPagedViewController else { return }
        let edge: UIRectEdge = owner?.view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        if edgeSwipe.state == .possible, edgeSwipe.edges != edge { edgeSwipe.edges = edge }
        reader.sumiGivePriority(to: edgeSwipe)
    }

    private func suspendReaderPans() {
        guard let owner else { return }
        var roots: [UIView] = []
        if let view = owner.readerViewController?.viewIfLoaded { roots.append(view) }
        if let surface = readerSurface() { roots.append(surface) }
        if let toolbar = owner.toolbar { roots.append(toolbar) }
        let customViews = ((owner.readerViewController?.toolbarItems ?? []) + (owner.toolbar?.items ?? []))
            .compactMap(\.customView)
        roots.append(contentsOf: customViews)
        panSuspension.suspend(in: roots, includingAncestorsOf: customViews, excluding: edgeSwipe)
    }

    private func updatePinchHost() {
        guard let owner, let pinch else { return }
        // Adaptive native bars can be UIKit siblings of the navigation view.
        // Observe both fingers at their common app window, while the delegate
        // permits recognition only for this active, unobscured reader.
        let host: UIView = owner.presentingViewController != nil
            ? (owner.view.window ?? owner.view) : owner.view
        guard pinch.view !== host else { return }
        #if DEBUG
        SumiBookPinchDiagnostics.record("host", ["oldHost": SumiBookPinchDiagnostics.typeName(pinch.view),
            "newHost": SumiBookPinchDiagnostics.typeName(host),
            "ownerWindow": SumiBookPinchDiagnostics.typeName(owner.view.window),
            "hasPresentingController": owner.presentingViewController != nil])
        #endif
        pinch.view?.removeGestureRecognizer(pinch)
        host.addGestureRecognizer(pinch)
    }

    func uninstall() {
        #if DEBUG
        if let pinch {
            SumiBookPinchDiagnostics.record("uninstall", ["host": SumiBookPinchDiagnostics.typeName(pinch.view),
                "state": pinch.state.rawValue])
        }
        #endif
        owner = nil
        interactive = false; isPinching = false
        panSuspension.restore()
        gestureHostObserver?.windowDidChange = nil
        gestureHostObserver?.removeFromSuperview()
        gestureHostObserver = nil
        let oldPinch = pinch
        let oldEdgeSwipe = edgeSwipe
        pinch = nil; edgeSwipe = nil
        if let oldPinch { oldPinch.view?.removeGestureRecognizer(oldPinch) }
        if let oldEdgeSwipe { oldEdgeSwipe.view?.removeGestureRecognizer(oldEdgeSwipe) }
    }

    func sourceFrame(in container: UIView) -> CGRect {
        if let frame = sourceFrameProvider?(container) { return frame }
        if let source = sourceView(), source.window != nil { return source.convert(source.bounds, to: container) }
        let height = min(container.bounds.height * 0.5, 300)
        return CGRect(x: container.bounds.midX - height * 0.34, y: container.bounds.midY - height / 2, width: height * 0.68, height: height)
    }

    func hoveringFrame(in container: UIView) -> CGRect {
        if let liftedFrame, liftedViewport == container.bounds.size { return liftedFrame }
        let area = container.bounds.insetBy(dx: 24, dy: 24)
        let aspect = closedPose == nil ? CGFloat(0.68) : SumiGridBookPose.canvasAspect
        let height = max(1, min(area.height * 0.7, area.width * 0.72 / aspect, 480))
        return CGRect(x: area.midX - height * aspect / 2, y: area.midY - height / 2 - 12,
                      width: height * aspect, height: height)
    }

    /// An explicit provider returning nil means its current cell has not been
    /// laid out (or is hidden). Never substitute the obsolete opening cell.
    func resolvedGridSourceFrame(in container: UIView) -> CGRect? {
        if let gridSourceFrameProvider { return gridSourceFrameProvider(container) }
        return sourceFrame(in: container)
    }

    func gridSourceFrame(in container: UIView) -> CGRect {
        resolvedGridSourceFrame(in: container) ?? hoveringFrame(in: container)
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let animation = SumiBookOpeningAnimator(opening: true, book: self); animator = animation; return animation
    }
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let animation = SumiBookOpeningAnimator(opening: false, book: self); animator = animation; return animation
    }
    func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? { interactive ? self : nil }
    var wantsInteractiveStart: Bool { interactive }
    func startInteractiveTransition(_ context: UIViewControllerContextTransitioning) {
        animator?.begin(context, interactive: true)
        if let pendingEnd { animator?.endInteractive(completing: pendingEnd.0, velocity: pendingEnd.1) }
    }
    func didFinishTransition() {
        animator = nil; interactive = false; pendingEnd = nil
        interactiveFraction = 0; isPinching = false
        panSuspension.restore()
    }

    func closingProgress(for fraction: CGFloat) -> CGFloat {
        isPinching ? min(1, max(0, fraction)) : SumiBookMotion.closeProgress(fraction)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let activeOwner = owner != nil && owner?.presentedViewController == nil && animator == nil && !interactive
            && owner?.presentingViewController != nil
        if let pinch = gestureRecognizer as? UIPinchGestureRecognizer {
            let windowMatches = pinch.view === owner?.viewIfLoaded?.window
            let allowed = activeOwner && windowMatches && pinch.numberOfTouches >= 2
            #if DEBUG
            SumiBookPinchDiagnostics.record("shouldBegin", ["hasOwner": owner != nil,
                "hasPresentedController": owner?.presentedViewController != nil,
                "presentedController": SumiBookPinchDiagnostics.typeName(owner?.presentedViewController),
                "hasPresentingController": owner?.presentingViewController != nil,
                "presentingController": SumiBookPinchDiagnostics.typeName(owner?.presentingViewController),
                "hasAnimator": animator != nil, "interactive": interactive,
                "host": SumiBookPinchDiagnostics.typeName(pinch.view),
                "ownerWindow": SumiBookPinchDiagnostics.typeName(owner?.viewIfLoaded?.window),
                "windowMatches": windowMatches, "scale": SumiBookPinchDiagnostics.number(pinch.scale),
                "velocity": SumiBookPinchDiagnostics.number(pinch.velocity),
                "touches": pinch.numberOfTouches, "allowed": allowed])
            #endif
            return allowed
        }
        return activeOwner
    }

    #if DEBUG
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === pinch {
            let point = touch.location(in: touch.window)
            SumiBookPinchDiagnostics.record("receiveTouch", ["ancestry": SumiBookPinchDiagnostics.ancestry(of: touch.view),
                "touchWindow": SumiBookPinchDiagnostics.typeName(touch.window), "phase": touch.phase.rawValue,
                "touchType": touch.type.rawValue, "x": point.x, "y": point.y,
                "touchesBeforeReceive": gestureRecognizer.numberOfTouches,
                "host": SumiBookPinchDiagnostics.typeName(gestureRecognizer.view),
                "ownerWindowMatches": touch.window === owner?.viewIfLoaded?.window])
        }
        return true
    }
    #endif

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // A native page pan may track just one finger while the other is over
        // the toolbar. Let the window pinch reach recognition, then suspend
        // those owned pans before taking the book's settled paper snapshot.
        let allowed: Bool
        if gestureRecognizer === pinch { allowed = otherGestureRecognizer is UIPanGestureRecognizer }
        else if otherGestureRecognizer === pinch { allowed = gestureRecognizer is UIPanGestureRecognizer }
        else { allowed = otherGestureRecognizer is UIPanGestureRecognizer }
        #if DEBUG
        if gestureRecognizer === pinch || otherGestureRecognizer === pinch {
            SumiBookPinchDiagnostics.record("simultaneous", [
                "firstClass": SumiBookPinchDiagnostics.typeName(gestureRecognizer),
                "firstState": gestureRecognizer.state.rawValue,
                "firstTouches": gestureRecognizer.numberOfTouches,
                "firstView": SumiBookPinchDiagnostics.typeName(gestureRecognizer.view),
                "firstIdentifier": gestureRecognizer.view?.accessibilityIdentifier ?? "",
                "secondClass": SumiBookPinchDiagnostics.typeName(otherGestureRecognizer),
                "secondState": otherGestureRecognizer.state.rawValue,
                "secondTouches": otherGestureRecognizer.numberOfTouches,
                "secondView": SumiBookPinchDiagnostics.typeName(otherGestureRecognizer.view),
                "secondIdentifier": otherGestureRecognizer.view?.accessibilityIdentifier ?? "",
                "allowed": allowed])
        }
        #endif
        return allowed
    }

    @objc private func backSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard let owner else { return }
        let sign: CGFloat = gesture.edges == .right ? -1 : 1
        guard let host = gesture.view ?? owner.view else { return }
        let space = host.window ?? host
        let width = max(1, host.bounds.width)
        let regularWidth = host.traitCollection.horizontalSizeClass == .regular
        let fraction = SumiBookMotion.backSwipeProgress(travel: gesture.translation(in: space).x * sign, width: width, regularWidth: regularWidth)
        let velocity = gesture.velocity(in: space).x * sign / SumiBookMotion.backSwipeDistance(width: width, regularWidth: regularWidth)
        switch gesture.state {
        case .began:
            isPinching = false
            interactive = true; pendingEnd = nil; interactiveFraction = fraction
            owner.dismiss(animated: true)
        case .changed:
            interactiveFraction = fraction; animator?.updateInteractive(fraction: fraction)
        case .ended, .cancelled, .failed:
            let complete = gesture.state == .ended && SumiBookMotion.completesBackSwipe(travel: gesture.translation(in: space).x * sign, velocity: gesture.velocity(in: space).x * sign, width: width, regularWidth: regularWidth)
            pendingEnd = (complete, velocity)
            animator?.endInteractive(completing: complete, velocity: velocity)
        default: break
        }
    }

    @objc private func closePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let owner else { return }
        let fraction = SumiBookMotion.pinchProgress(scale: gesture.scale)
        let velocity = SumiBookMotion.pinchVelocity(gesture.velocity)
        switch gesture.state {
        case .began, .changed:
            // Native recognition can start with tiny outward sampling noise.
            // Observe both fingers first, and lift the book only after an
            // intentional inward movement. An outward pinch leaves it still.
            if !isPinching {
                guard gesture.scale <= 0.98, !interactive, animator == nil,
                      owner.presentedViewController == nil else { return }
                #if DEBUG
                SumiBookPinchDiagnostics.record("pinchBegan", ["scale": SumiBookPinchDiagnostics.number(gesture.scale),
                    "velocity": SumiBookPinchDiagnostics.number(gesture.velocity),
                    "touches": gesture.numberOfTouches, "fraction": fraction])
                #endif
                isPinching = true
                interactive = true; pendingEnd = nil; interactiveFraction = fraction
                chromeTransition(true)
                suspendReaderPans()
                owner.dismiss(animated: true)
            } else {
                interactiveFraction = fraction
                animator?.updateInteractive(fraction: fraction)
            }
        case .ended, .cancelled, .failed:
            guard isPinching, interactive else { return }
            let complete = gesture.state == .ended && SumiBookMotion.completes(swipe: fraction, velocity: velocity)
            #if DEBUG
            SumiBookPinchDiagnostics.record("pinchEnded", ["state": gesture.state.rawValue,
                "scale": SumiBookPinchDiagnostics.number(gesture.scale),
                "velocity": SumiBookPinchDiagnostics.number(gesture.velocity), "fraction": fraction,
                "normalizedVelocity": SumiBookPinchDiagnostics.number(velocity), "complete": complete])
            #endif
            pendingEnd = (complete, velocity)
            animator?.endInteractive(completing: complete, velocity: velocity)
        default: break
        }
    }
}
#endif
