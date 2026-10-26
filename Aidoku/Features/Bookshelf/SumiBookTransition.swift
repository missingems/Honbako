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
    var chromeTransition: (Bool) -> Void = { _ in }
    var openingCancellationBegan: () -> Void = {}
    var openingCancelled: () -> Void = {}
    private var animator: SumiBookOpeningAnimator?
    private weak var owner: SumiDirectReaderController?
    private(set) var edgeSwipe: UIScreenEdgePanGestureRecognizer?
    private(set) var interactiveFraction: CGFloat = 0
    private var interactive = false
    private var pendingEnd: (Bool, CGFloat)?

    init(coverImage: UIImage?, closedPose: SumiGridBookPose? = nil, liftedFrame: CGRect? = nil, liftedViewport: CGSize? = nil, sourceFrameProvider: ((UIView) -> CGRect?)? = nil, gridSourceFrameProvider: ((UIView) -> CGRect?)? = nil, readerSurface: @escaping () -> UIView?, paired: @escaping () -> Bool, sourceView: @escaping () -> UIView?) {
        self.sourceFrameProvider = sourceFrameProvider
        self.gridSourceFrameProvider = gridSourceFrameProvider
        self.closedPose = closedPose; self.liftedFrame = liftedFrame; self.liftedViewport = liftedViewport
        self.coverImage = coverImage; self.readerSurface = readerSurface; self.paired = paired; self.sourceView = sourceView
    }

    func install(on owner: SumiDirectReaderController) {
        self.owner = owner
        let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(backSwipe(_:)))
        gesture.edges = owner.view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        gesture.delegate = self
        (owner.readerViewController?.view ?? owner.view).addGestureRecognizer(gesture); edgeSwipe = gesture
        owner.interactivePopGestureRecognizer?.isEnabled = false
        if #available(iOS 26.0, *) { owner.interactiveContentPopGestureRecognizer?.isEnabled = false }
        prioritizeBackSwipe()
    }

    func prioritizeBackSwipe() {
        guard let edgeSwipe, let reader = owner?.readerViewController?.reader as? ReaderPagedViewController else { return }
        let edge: UIRectEdge = owner?.view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        if edgeSwipe.state == .possible, edgeSwipe.edges != edge { edgeSwipe.edges = edge }
        reader.sumiGivePriority(to: edgeSwipe)
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

    func gridSourceFrame(in container: UIView) -> CGRect {
        gridSourceFrameProvider?(container) ?? sourceFrame(in: container)
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
    func didFinishTransition() { animator = nil; interactive = false; pendingEnd = nil }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let owner, owner.presentedViewController == nil, animator == nil, owner.presentingViewController != nil else { return false }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        otherGestureRecognizer is UIPanGestureRecognizer
    }

    @objc private func backSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard let owner else { return }
        let sign: CGFloat = gesture.edges == .right ? -1 : 1
        guard let space = owner.view.window ?? owner.view else { return }
        let width = max(1, space.bounds.width)
        let fraction = min(1, max(0, gesture.translation(in: space).x * sign / width))
        let velocity = gesture.velocity(in: space).x * sign / width
        switch gesture.state {
        case .began:
            interactive = true; pendingEnd = nil; interactiveFraction = fraction
            owner.dismiss(animated: true)
        case .changed:
            interactiveFraction = fraction; animator?.updateInteractive(fraction: fraction)
        case .ended, .cancelled, .failed:
            let complete = gesture.state == .ended && SumiBookMotion.completes(swipe: fraction, velocity: velocity)
            pendingEnd = (complete, velocity)
            animator?.endInteractive(completing: complete, velocity: velocity)
        default: break
        }
    }
}
#endif
