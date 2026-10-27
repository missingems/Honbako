@testable import Sumi
import Testing
import UIKit

@MainActor
struct SumiBookClosingTransitionTests {
    @Test("Interactive release reports finish or cancellation once before visual completion")
    func interactiveOutcomePrecedesCompletion() async throws {
        for completes in [false, true] {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive })
            let window = UIWindow(windowScene: scene)
            let host = UIViewController()
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            let container = UIView(frame: CGRect(x: 0, y: 0, width: 450, height: 800))
            host.view.addSubview(container)
            let context = ClosingContext(container: container)
            context.interactiveValue = true
            let transition = SumiBookTransition(coverImage: nil,
                sourceFrameProvider: { _ in CGRect(x: 20, y: 30, width: 68, height: 100) },
                readerSurface: { context.from.view }, paired: { false }, sourceView: { nil })
            let animator = SumiBookOpeningAnimator(opening: false, book: transition)
            animator.begin(context, interactive: true)
            animator.updateInteractive(fraction: completes ? 0.75 : 0.4)
            animator.endInteractive(completing: completes, velocity: 0)
            let expected = completes ? "finish" : "cancel"
            #expect(context.outcomeEvents == [expected], "UIKit leaves touch tracking when the finger releases")
            #expect(context.completed == nil, "The book still has a visual settling animation")
            animator.endInteractive(completing: !completes, velocity: 0)
            #expect(context.outcomeEvents == [expected], "Repeated release cannot change or duplicate its outcome")
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while context.completed == nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(context.completed == completes)
            #expect(context.outcomeEvents == [expected, "complete:\(completes)"])
        }
    }

    @Test("An interrupted interactive close reports cancellation if no finger release arrived")
    func interruptionReportsFallbackOutcomeOnce() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 450, height: 800))
        host.view.addSubview(container)
        let context = ClosingContext(container: container)
        context.interactiveValue = true
        let transition = SumiBookTransition(coverImage: nil,
            sourceFrameProvider: { _ in CGRect(x: 20, y: 30, width: 68, height: 100) },
            readerSurface: { context.from.view }, paired: { false }, sourceView: { nil })
        let animator = SumiBookOpeningAnimator(opening: false, book: transition)
        animator.begin(context, interactive: true)
        container.bounds.size.width += 1
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while context.completed == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(context.completed == false)
        #expect(context.outcomeEvents == ["cancel", "complete:false"])
    }

    @Test("Opening accepts UIKit's omitted retained presenter without removing its original hierarchy")
    func opensWithRetainedPresenter() async throws {
        try await retainedPresenterTransition(opening: true)
    }

    @Test("Closing accepts an omitted retained presenter even with custom style and never reparents its search or grid")
    func closesWithRetainedPresenter() async throws {
        try await retainedPresenterTransition(opening: false)
    }

    private func retainedPresenterTransition(opening: Bool) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 450, height: 800))
        host.view.addSubview(container)
        let context = ClosingContext(container: container)
        context.omittedPresentingView = opening ? .from : .to
        if !opening { context.presentationStyleOverride = .custom }
        let presenter = opening ? context.from.view! : context.to.view!
        host.view.insertSubview(presenter, belowSubview: container)
        let presenterFrame = CGRect(x: 8, y: 12, width: 420, height: 760)
        presenter.frame = presenterFrame
        let surface = opening ? context.to.view! : context.from.view!
        let transition = SumiBookTransition(coverImage: nil,
            sourceFrameProvider: { _ in CGRect(x: 30, y: 50, width: 68, height: 100) },
            readerSurface: { surface }, paired: { false }, sourceView: { nil })
        let animator = SumiBookOpeningAnimator(opening: opening, book: transition)
        animator.begin(context, interactive: false)
        #expect(context.completed == nil, "A missing retained presenting view must not reject the book animation")
        #expect(presenter.superview === host.view)
        #expect(presenter.frame == presenterFrame)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while context.completed == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(context.completed == true)
        #expect(presenter.superview === host.view)
        #expect(presenter.frame == presenterFrame, "The retained Search layout is never moved into transition-container coordinates")
    }

    @Test("Closing a rotated portrait reader keeps its settled slot and single-page geometry through the whole return")
    func rotatedCloseKeepsSettledGeometry() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 450, height: 800))
        host.view.addSubview(container)
        let context = ClosingContext(container: container)
        let portraitSlot = CGRect(x: 154, y: 32, width: 148, height: 218)
        var source = portraitSlot
        var paired = false
        let print = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 450)).image { output in
            UIColor.white.setFill(); output.fill(CGRect(x: 0, y: 0, width: 300, height: 450))
        }
        let transition = SumiBookTransition(coverImage: print,
            gridSourceFrameProvider: { _ in source }, readerSurface: { context.from.view },
            paired: { paired }, sourceView: { nil })
        let animator = SumiBookOpeningAnimator(opening: false, book: transition)
        animator.begin(context, interactive: false)
        let stage = try #require(context.containerView.subviews.compactMap { $0 as? SumiBookStageView }.first)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while (stage.completedProgress ?? 1) >= 0.98, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect((stage.completedProgress ?? 1) < 0.98)
        // Simulate a stale lazy-grid measurement arriving after the library's
        // settled portrait cell has already started receiving the book.
        source = CGRect(x: 600, y: 42, width: 148, height: 218)
        paired = true
        try await Task.sleep(for: .milliseconds(60))
        let progress = try #require(stage.completedProgress)
        #expect(progress > 0 && progress < 1)
        #expect(stage.completedSourceFrame == portraitSlot)
        let expected = SumiBookReturnPose(progress: progress, origin: portraitSlot)
            .paperFrame(in: stage.bounds, paired: false)
        let printedPage = try #require(stage.layer.sublayers?.first)
        #expect(abs(printedPage.frame.minX - expected.minX) < 0.001)
        #expect(abs(printedPage.frame.width - expected.width) < 0.001)
        let completionDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while context.completed == nil, ContinuousClock.now < completionDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(context.completed == true)
    }
}

@MainActor
private final class ClosingContext: NSObject, UIViewControllerContextTransitioning {
    let containerView: UIView
    let from = UIViewController()
    let to = UIViewController()
    var completed: Bool?
    var interactiveValue = false
    var outcomeEvents: [String] = []
    var omittedPresentingView: UITransitionContextViewKey?
    var presentationStyleOverride: UIModalPresentationStyle?
    var isAnimated: Bool { true }
    var isInteractive: Bool { interactiveValue }
    var transitionWasCancelled: Bool { false }
    var presentationStyle: UIModalPresentationStyle {
        presentationStyleOverride ?? (omittedPresentingView == nil ? .fullScreen : .overFullScreen)
    }
    var targetTransform: CGAffineTransform { .identity }

    init(container: UIView) {
        containerView = container
        super.init()
        from.view.backgroundColor = .white
        to.view.backgroundColor = .systemBackground
        containerView.addSubview(from.view)
        from.view.frame = containerView.bounds
    }
    func updateInteractiveTransition(_ percentComplete: CGFloat) {}
    func finishInteractiveTransition() { outcomeEvents.append("finish") }
    func cancelInteractiveTransition() { outcomeEvents.append("cancel") }
    func pauseInteractiveTransition() {}
    func completeTransition(_ didComplete: Bool) {
        completed = didComplete
        outcomeEvents.append("complete:\(didComplete)")
    }
    func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? { key == .from ? from : to }
    func view(forKey key: UITransitionContextViewKey) -> UIView? {
        if key == omittedPresentingView { return nil }
        return key == .from ? from.view : to.view
    }
    func initialFrame(for vc: UIViewController) -> CGRect { containerView.bounds }
    func finalFrame(for vc: UIViewController) -> CGRect { containerView.bounds }
}
