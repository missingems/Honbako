@testable import Sumi
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiBookReturnVisibilityTests {
    @Test("A completed opening keeps the library slot empty while its reader owns the book")
    func completedOpeningKeepsSourceHidden() async throws {
        try await verifySourceLifetime(opening: true, completes: true)
    }

    @Test("Cancelling swipe-back keeps the source hidden behind the restored reader")
    func cancelledCloseKeepsSourceHidden() async throws {
        try await verifySourceLifetime(opening: false, completes: false)
    }

    @Test("A cancelled opening restores its library cover")
    func cancelledOpeningRestoresSource() async throws {
        try await verifySourceLifetime(opening: true, completes: false)
    }

    @Test("A completed close reveals its cover only once the closed hero reaches the new receiving slot")
    func completedCloseRevealsOnlyAtHandoff() async throws {
        try await verifySourceLifetime(opening: false, completes: true)
    }

    private func verifySourceLifetime(opening: Bool, completes: Bool) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 450, height: 800))
        host.view.addSubview(container)
        let context = ReturnVisibilityContext(container: container)
        // The destination models a book that moved after its reading history
        // was saved. Visibility must follow the current slot, not the old one.
        let oldSlot = CGRect(x: 20, y: 40, width: 100, height: 150)
        let newSlot = CGRect(x: 240, y: 400, width: 100, height: 150)
        let receiver = UIView(frame: newSlot)
        receiver.backgroundColor = .purple
        receiver.isHidden = true
        context.to.view.addSubview(receiver)
        let transition = SumiBookTransition(coverImage: nil,
            sourceFrameProvider: { _ in oldSlot }, gridSourceFrameProvider: { _ in newSlot },
            readerSurface: { opening ? context.to.view : context.from.view },
            paired: { false }, sourceView: { receiver })
        var hero: SumiBookStageView?
        var earlyReveal = false
        var handoffCount = 0
        transition.sourceVisibility = { hidden in
            if !hidden, !opening, completes, context.completed == nil, handoffCount == 0 {
                earlyReveal = true
            }
            receiver.isHidden = hidden
        }
        transition.revealSourceForHandoff = {
            #expect(hero?.superview === container)
            #expect(hero?.completedProgress == 0)
            #expect(hero?.completedSourceFrame == newSlot)
            handoffCount += 1
            receiver.isHidden = false
        }
        let animator = SumiBookOpeningAnimator(opening: opening, book: transition)
        animator.begin(context, interactive: !opening)
        hero = container.subviews.compactMap { $0 as? SumiBookStageView }.first
        if opening, !completes {
            let stage = try #require(hero)
            let cancel = try #require(stage.accessibilityCustomActions?.first)
            #expect(cancel.actionHandler?(cancel) == true)
        } else if !opening {
            animator.updateInteractive(fraction: completes ? 0.8 : 0.25)
            animator.endInteractive(completing: completes, velocity: 0)
        }
        let deadline = ContinuousClock.now + .seconds(4)
        while context.completed == nil, ContinuousClock.now < deadline {
            if !opening, completes, let progress = hero?.completedProgress, progress > 0.002 {
                #expect(receiver.isHidden, "The receiving cover must not duplicate a moving hero")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(context.completed == completes)
        #expect(receiver.isHidden == (opening == completes),
                "The reader owns one visible edition until a completed close or cancelled opening returns it")
        #expect(!earlyReveal)
        #expect(handoffCount == (!opening && completes ? 1 : 0))
    }
}

@MainActor
private final class ReturnVisibilityContext: NSObject, UIViewControllerContextTransitioning {
    let containerView: UIView
    let from = UIViewController()
    let to = UIViewController()
    var completed: Bool?
    var isAnimated: Bool { true }
    var isInteractive: Bool { true }
    var transitionWasCancelled: Bool { false }
    var presentationStyle: UIModalPresentationStyle { .fullScreen }
    var targetTransform: CGAffineTransform { .identity }

    init(container: UIView) {
        containerView = container
        super.init()
        from.view.backgroundColor = .white
        to.view.backgroundColor = .systemBackground
        container.addSubview(from.view)
        from.view.frame = container.bounds
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
