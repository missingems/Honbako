@testable import Sumi
import Testing
import UIKit

@MainActor
struct SumiBookClosingTransitionTests {
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
    var isAnimated: Bool { true }
    var isInteractive: Bool { false }
    var transitionWasCancelled: Bool { false }
    var presentationStyle: UIModalPresentationStyle { .fullScreen }
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
    func finishInteractiveTransition() {}
    func cancelInteractiveTransition() {}
    func pauseInteractiveTransition() {}
    func completeTransition(_ didComplete: Bool) { completed = didComplete }
    func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? { key == .from ? from : to }
    func view(forKey key: UITransitionContextViewKey) -> UIView? { key == .from ? from.view : to.view }
    func initialFrame(for vc: UIViewController) -> CGRect { containerView.bounds }
    func finalFrame(for vc: UIViewController) -> CGRect { containerView.bounds }
}
