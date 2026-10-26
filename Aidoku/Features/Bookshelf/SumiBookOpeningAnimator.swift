#if SUMI
import UIKit

final class SumiBookOpeningAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let opening: Bool
    private let book: SumiBookTransition
    private var context: UIViewControllerContextTransitioning?
    private var stage: SumiBookStageView?
    private var paper: UIView?
    private let backdrop = UIView()
    private let returnDimming = UIView()
    private var clock: CADisplayLink?
    private var lastAnimationTimestamp: CFTimeInterval?
    private var animationTime: TimeInterval = 0
    private var runFrom: CGFloat = 0
    private var runTo: CGFloat = 1
    private var runVelocity: CGFloat = 0
    private var swipe: CGFloat = 0
    private var interactive = false
    private var settling = false
    private var frameSize = CGSize.zero
    private var originalCenter = CGPoint.zero
    private var trailingFrames = 0
    private var finished = false
    private var sourceHidden = false
    private var lastCompletedStageFrames = 0
    private var lastStageCompletionTime: CFTimeInterval = 0
    private var observer: NSObjectProtocol?
    private var outsideTap: UITapGestureRecognizer?
    private var isCancellingOpening = false
    private var cancellationHoverFrame: CGRect?
    private var cancellationPaperFrame: CGRect?
    private var cancellationOpenness: CGFloat = 1
    private var cancellationCover: UIImageView?
    private var returnSourceFrame: CGRect?
    private var pairedPaper = false

    init(opening: Bool, book: SumiBookTransition) { self.opening = opening; self.book = book }
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0.18 : 0.65
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) { begin(context, interactive: false) }

    func begin(_ context: UIViewControllerContextTransitioning, interactive: Bool) {
        guard let from = context.view(forKey: .from), let to = context.view(forKey: .to),
              let destination = context.viewController(forKey: .to) else {
            context.completeTransition(false); book.didFinishTransition(); return
        }
        self.context = context; self.interactive = interactive
        book.chromeTransition(true)
        let container = context.containerView
        if opening { container.addSubview(to) } else { container.insertSubview(to, belowSubview: from) }
        to.frame = context.finalFrame(for: destination)
        if to.frame.isEmpty { to.frame = container.bounds }
        to.layoutIfNeeded()
        let moving = opening ? to : from
        paper = moving; originalCenter = moving.center; frameSize = container.bounds.size
        backdrop.frame = container.bounds; backdrop.backgroundColor = .white
        backdrop.alpha = 0
        container.insertSubview(backdrop, belowSubview: moving)
        if !opening {
            returnDimming.frame = container.bounds
            returnDimming.backgroundColor = .black
            returnDimming.alpha = 0
            container.insertSubview(returnDimming, belowSubview: backdrop)
        }
        let surface = book.readerSurface() ?? moving
        let image = UIAccessibility.isReduceMotionEnabled ? nil : Self.capture(surface)
        pairedPaper = book.paired()
        if !UIAccessibility.isReduceMotionEnabled, let image {
            stage = try? SumiBookStageView(frame: container.bounds, cover: book.coverImage, spread: image, paired: pairedPaper, closedPose: book.closedPose)
        }
        if let stage { stage.alpha = 0; container.addSubview(stage) }
        if opening {
            stage?.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Cancel opening") { [weak self] _ in
                guard let self, !self.finished, !self.isCancellingOpening else { return false }
                self.beginOpeningCancellation()
                return true
            }]
            let tap = UITapGestureRecognizer(target: self, action: #selector(cancelOpeningFromTap(_:)))
            container.addGestureRecognizer(tap)
            outsideTap = tap
        }
        lastStageCompletionTime = CACurrentMediaTime()
        swipe = opening ? 0 : 1
        runFrom = interactive ? 0 : swipe
        runTo = opening ? 1 : 0
        settling = !interactive
        if opening { moving.alpha = 0 }
        observer = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.finish(completed: self.opening && !self.isCancellingOpening)
            }
        }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        let maximum = Float(container.window?.windowScene?.screen.maximumFramesPerSecond ?? 60)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
        link.add(to: .main, forMode: .common); clock = link
        if interactive { swipe = book.interactiveFraction; settling = false }
    }

    func updateInteractive(fraction: CGFloat) {
        guard interactive, !settling else { return }
        swipe = min(1, max(0, fraction))
        context?.updateInteractiveTransition(swipe)
    }

    func endInteractive(completing: Bool, velocity: CGFloat) {
        guard interactive, !settling else { return }
        runFrom = swipe; runTo = completing ? 1 : 0; runVelocity = velocity
        lastAnimationTimestamp = nil; animationTime = 0; settling = true
    }

    @objc private func cancelOpeningFromTap(_ gesture: UITapGestureRecognizer) {
        guard let context, opening, !finished, !isCancellingOpening else { return }
        let container = context.containerView
        let point = gesture.location(in: container)
        let visibleSource = stage?.completedSourceFrame ?? book.sourceFrame(in: container)
        if let stage, stage.completedFrames >= 2 {
            guard !stage.containsBook(at: point) else { return }
        } else {
            guard !visibleSource.contains(point) else { return }
        }
        beginOpeningCancellation()
    }

    private func beginOpeningCancellation() {
        guard let context, opening, !finished, !isCancellingOpening else { return }
        let container = context.containerView
        let visibleProgress = stage?.completedProgress ?? 0
        let visibleSource = stage?.completedSourceFrame ?? book.sourceFrame(in: container)
        // If cancellation precedes the first stage frame, return the exact
        // hovering edition already on screen.
        if stage == nil || (stage?.completedFrames ?? 0) < 2 {
            let cover = UIImageView(image: book.sourceView().flatMap(Self.capture))
            cover.frame = visibleSource
            cover.contentMode = .scaleToFill
            cover.isUserInteractionEnabled = false
            container.addSubview(cover)
            cancellationCover = cover
            stage?.removeFromSuperview()
            stage = nil
        }
        isCancellingOpening = true
        cancellationHoverFrame = visibleSource
        cancellationPaperFrame = SumiBookMotion.paperFrame(source: visibleSource, destination: container.bounds,
                                                          paired: pairedPaper, progress: visibleProgress)
        cancellationOpenness = visibleProgress
        runFrom = 1
        runTo = 0
        runVelocity = 0
        swipe = runFrom
        animationTime = 0
        lastAnimationTimestamp = nil
        trailingFrames = 0
        settling = true
        returnDimming.frame = container.bounds
        returnDimming.backgroundColor = .black
        returnDimming.alpha = 0.68
        container.insertSubview(returnDimming, belowSubview: backdrop)
        book.sourceVisibility(true)
        sourceHidden = true
        book.openingCancellationBegan()
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let context, !finished else { return }
        guard context.containerView.bounds.size == frameSize else {
            finish(completed: opening && !isCancellingOpening); return
        }
        // Keep the source visible through the first compositor handoff.
        if let stage {
            if stage.completedFrames != lastCompletedStageFrames {
                lastCompletedStageFrames = stage.completedFrames
                lastStageCompletionTime = link.targetTimestamp
            }
            if link.targetTimestamp - lastStageCompletionTime > 10 {
                stage.removeFromSuperview(); self.stage = nil
            }
        }
        let ready = stage == nil || (stage?.completedFrames ?? 0) >= 2
        if ready, (!opening || isCancellingOpening), returnSourceFrame == nil {
            // The hidden library may still have its pre-rotation grid geometry
            // when UIKit first reattaches it. Keep the reader fully visible for
            // the initial compositor handoff, then use one settled return slot
            // throughout the close instead of steering toward a moving target.
            let library = context.view(forKey: opening ? .from : .to)
            library?.setNeedsLayout()
            library?.layoutIfNeeded()
            returnSourceFrame = book.gridSourceFrame(in: context.containerView)
        }
        if ready, !sourceHidden { book.sourceVisibility(true); sourceHidden = true }
        if ready, settling {
            if let lastAnimationTimestamp {
                // The first layout must not consume the opening animation.
                animationTime += min(1.0 / 30, max(0, link.targetTimestamp - lastAnimationTimestamp))
            }
            lastAnimationTimestamp = link.targetTimestamp
            let time = animationTime * (opening && !isCancellingOpening ? 1 : 0.7)
            if UIAccessibility.isReduceMotionEnabled {
                swipe = runFrom + (runTo - runFrom) * min(1, CGFloat(time / 0.18))
            } else {
                swipe = SumiBookMotion.spring(from: runFrom, to: runTo, velocity: runVelocity, time: time)
            }
            if abs(swipe - runTo) < 0.002, time > 0.08 {
                swipe = runTo; trailingFrames += 1
            }
        }
        let progress = interactive ? 1 - SumiBookMotion.closeProgress(swipe) : min(1, max(0, swipe))
        apply(progress: progress, delta: link.targetTimestamp - link.timestamp)
        let returning = returnPose(progress: progress, in: context.containerView)
        let endOpenness = opening && !isCancellingOpening ? progress : returning.openness
        let endSource = opening && !isCancellingOpening ? book.sourceFrame(in: context.containerView)
            : returning.sourceFrame
        let renderedSource = stage?.completedSourceFrame
        let sourceMatches = renderedSource.map {
            abs($0.minX - endSource.minX) < 0.5 && abs($0.minY - endSource.minY) < 0.5
                && abs($0.width - endSource.width) < 0.5 && abs($0.height - endSource.height) < 0.5
        } == true
        let renderedEnd = stage == nil || (sourceMatches
            && stage?.completedProgress.map { abs($0 - endOpenness) < 0.002 } == true)
        if trailingFrames >= 2, renderedEnd {
            finish(completed: isCancellingOpening ? false : interactive ? runTo == 1 : true)
        }
    }

    private func apply(progress: CGFloat, delta: TimeInterval) {
        guard let context, let paper else { return }
        let container = context.containerView
        if UIAccessibility.isReduceMotionEnabled, !isCancellingOpening {
            paper.transform = .identity; paper.center = originalCenter
            paper.alpha = progress; backdrop.alpha = progress
            return
        }
        let returning = returnPose(progress: progress, in: container)
        let source = opening && !isCancellingOpening ? book.sourceFrame(in: container) : returning.sourceFrame
        let openness = opening && !isCancellingOpening ? progress : returning.openness
        if let cancellationCover {
            cancellationCover.frame = returning.coverFrame(startingAt: cancellationHoverFrame ?? source)
            paper.alpha = 0
            backdrop.alpha = 0
            returnDimming.alpha = returning.gridDimming
            return
        }
        if let stage, stage.completedFrames < 2 {
            stage.alpha = 0; paper.alpha = opening ? 0 : 1; backdrop.alpha = 0
            if !stage.draw(progress: opening ? 0 : 1, source: source, deltaTime: delta) {
                self.stage = nil; stage.removeFromSuperview()
            }
            return
        }
        let frame = opening && !isCancellingOpening
            ? SumiBookMotion.paperFrame(source: source, destination: container.bounds, paired: pairedPaper, progress: openness)
            : returning.paperFrame(in: container.bounds, paired: pairedPaper, startingAt: cancellationPaperFrame)
        paper.transform = CGAffineTransform(scaleX: frame.width / max(1, paper.bounds.width), y: frame.height / max(1, paper.bounds.height))
        paper.center = CGPoint(x: frame.midX, y: frame.midY)
        backdrop.alpha = stage == nil ? min(1, openness / 0.4) : 0
        if !opening || isCancellingOpening { returnDimming.alpha = returning.gridDimming }
        if let stage {
            // Keep the print opaque until its open geometry exactly matches
            // the native reader, avoiding ghost pages during the handoff.
            paper.alpha = 0
            stage.alpha = 1
            if !stage.draw(progress: openness, source: source, paperFrame: frame, deltaTime: delta) {
                self.stage = nil; stage.removeFromSuperview(); paper.alpha = progress
            }
        } else {
            paper.alpha = UIAccessibility.isReduceMotionEnabled ? progress : min(1, progress / 0.5)
        }
    }

    private func returnPose(progress: CGFloat, in container: UIView) -> SumiBookReturnPose {
        SumiBookReturnPose(progress: progress, origin: returnSourceFrame ?? book.gridSourceFrame(in: container),
                           initialOpenness: isCancellingOpening ? cancellationOpenness : 1)
    }

    private func finish(completed: Bool) {
        guard !finished, let context else { return }
        finished = true; clock?.invalidate(); clock = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil
        if let outsideTap { outsideTap.view?.removeGestureRecognizer(outsideTap) }; outsideTap = nil
        paper?.transform = .identity; paper?.center = originalCenter; paper?.alpha = 1
        stage?.removeFromSuperview(); stage = nil
        cancellationCover?.removeFromSuperview(); cancellationCover = nil
        backdrop.removeFromSuperview(); returnDimming.removeFromSuperview()
        if opening, !completed {
            paper?.removeFromSuperview()
            book.openingCancelled()
        }
        book.sourceVisibility(false)
        book.chromeTransition(false)
        if interactive {
            if completed { context.finishInteractiveTransition() } else { context.cancelInteractiveTransition() }
        }
        context.completeTransition(completed)
        self.context = nil
        book.didFinishTransition()
    }

    private static func capture(_ view: UIView) -> UIImage? {
        guard view.bounds.width > 1, view.bounds.height > 1 else { return nil }
        view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat(); format.scale = min(2, view.traitCollection.displayScale)
        return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in view.layer.render(in: context.cgContext) }
    }

    deinit { clock?.invalidate(); if let observer { NotificationCenter.default.removeObserver(observer) } }
}
#endif
