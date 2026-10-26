@testable import Sumi
import AidokuRunner
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiReaderHoverTests {
    @Test("Loading cancels only outside the cover and preserves accessible cancellation without an X")
    func loadingCancellation() {
        let book = SumiBook(manga: AidokuRunner.Manga(sourceKey: "sumi-hover-test", key: "cancel", title: "Cancel book"))
        let loading = SumiReaderLoadingViewController(book: book)
        loading.loadViewIfNeeded()
        loading.view.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        loading.zoomSourceView.frame = CGRect(x: 120, y: 140, width: 160, height: 260)
        loading.view.setNeedsLayout()
        loading.view.layoutIfNeeded()
        var closeCount = 0
        var retryCount = 0
        loading.closeBook = { closeCount += 1 }
        loading.retry = { retryCount += 1 }

        loading.cancelOpeningIfOutsideCover(at: CGPoint(x: 200, y: 270))
        #expect(closeCount == 0, "The cover ignores taps")
        let views = descendants(of: loading.view)
        let pill = views.first { $0.accessibilityIdentifier == "Sumi.Book.LoadingPill" }
        #expect(pill?.superview === loading.zoomSourceView)
        #expect((pill?.frame.minY ?? 0) > loading.zoomSourceView.bounds.maxY)
        #expect(!loading.zoomSourceView.clipsToBounds)
        #expect(!views.contains { $0.accessibilityIdentifier == "Sumi.Book.CoverDimming" })
        if let pill {
            let originalSize = pill.bounds.size
            loading.zoomSourceView.frame.size = CGSize(width: 220, height: 340)
            // Only the cover changes size during its lift. Its own layout must
            // keep the pill below it without needing a root-controller layout.
            loading.zoomSourceView.layoutIfNeeded()
            #expect(pill.frame.minY == loading.zoomSourceView.bounds.maxY + 16)
            #expect(pill.frame.midX == loading.zoomSourceView.bounds.midX)
            #expect(pill.bounds.size == originalSize, "The pill stays at normal control size while the book grows")
        }
        if let pill {
            let center = pill.convert(CGPoint(x: pill.bounds.midX, y: pill.bounds.midY), to: loading.view)
            loading.cancelOpeningIfOutsideCover(at: center)
            #expect(closeCount == 1, "The loading label is outside the cover, so tapping it also cancels")
        }
        loading.cancelOpeningIfOutsideCover(at: CGPoint(x: 20, y: 20))
        #expect(closeCount == 2)
        loading.showError("Please try again")
        let buttons = descendants(of: loading.view).compactMap { $0 as? UIButton }
        #expect(buttons.allSatisfy { $0.accessibilityIdentifier != "SumiReader.Close" })
        buttons.first { $0.title(for: .normal) == "Retry" }?.sendActions(for: .touchUpInside)
        #expect(retryCount == 1)
        #expect(closeCount == 2, "Retry must not also close the book")
        #expect(loading.view.accessibilityCustomActions?.contains { $0.name == "Cancel opening" } == true)
        #expect(loading.accessibilityPerformEscape())
        #expect(closeCount == 3)
    }

    @Test("Cancelling loading lowers the original cover into the current source frame")
    func returnToCurrentSource() async {
        let book = SumiBook(manga: AidokuRunner.Manga(sourceKey: "sumi-hover-test", key: "return", title: "Return book"))
        let snapshot = UIGraphicsImageRenderer(size: CGSize(width: 68, height: 100)).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 68, height: 100))
        }
        let loading = SumiReaderLoadingViewController(book: book, snapshot: snapshot)
        loading.loadViewIfNeeded()
        loading.view.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        loading.zoomSourceView.frame = CGRect(x: 120, y: 140, width: 160, height: 260)
        let destination = CGRect(x: 14, y: 26, width: 90, height: 132)
        var sourceReads = 0
        await withCheckedContinuation { continuation in
            loading.returnToSource(frame: {
                sourceReads += 1
                return destination
            }) { continuation.resume() }
        }
        #expect(sourceReads == 1)
        #expect(loading.zoomSourceView.frame == destination)
        #expect(loading.coverSnapshot() === snapshot, "Return must retain the original print without changing its brightness")
        #expect(loading.zoomSourceView.layer.animation(forKey: "Sumi.Hover") == nil)
        #expect(loading.zoomSourceView.layer.shadowOpacity == 0)
        #expect(!loading.view.isUserInteractionEnabled)
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @Test("The hover starts at the lift endpoint and survives layout and opening without a pose reset")
    func hoverContinuity() async throws {
        let book = SumiBook(manga: AidokuRunner.Manga(sourceKey: "sumi-hover-test", key: "book", title: "Hover book"))
        let snapshot = UIGraphicsImageRenderer(size: CGSize(width: 68, height: 100)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 68, height: 100))
        }
        let loading = SumiReaderLoadingViewController(book: book, snapshot: snapshot)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }, "Hover needs the hosted app's visible scene")
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .alert + 1
        window.rootViewController = loading
        window.makeKeyAndVisible()
        defer {
            let wasKeyWindow = window.isKeyWindow
            window.isHidden = true
            window.rootViewController = nil
            if wasKeyWindow { previousKeyWindow?.makeKey() }
        }
        // Give UIKit one display cycle to attach this test window before asking
        // its lift completion to start the continuous Core Animation hover.
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(25))
        loading.beginLoading(from: nil)
        let cover = loading.zoomSourceView
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while cover.layer.animation(forKey: "Sumi.Hover") == nil,
              !UIAccessibility.isReduceMotionEnabled, ContinuousClock.now < deadline {
            window.layoutIfNeeded()
            CATransaction.flush()
            try await Task.sleep(for: .milliseconds(25))
        }
        if !UIAccessibility.isReduceMotionEnabled {
            let hover = try #require(cover.layer.animation(forKey: "Sumi.Hover") as? CAKeyframeAnimation,
                                     "The lift must finish and start hovering within two seconds")
            #expect((hover.values?.first as? NSNumber)?.doubleValue == 0)
            // Sample away from the first zero-valued hover frame so a reset to
            // the model pose would be observable during prepareOpening.
            try await Task.sleep(for: .milliseconds(250))
        }
        let originalFrame = cover.frame
        loading.additionalSafeAreaInsets = UIEdgeInsets(top: 40, left: 60, bottom: 0, right: 0)
        loading.view.setNeedsLayout()
        loading.view.layoutIfNeeded()
        #expect(cover.frame == originalFrame, "Preparing reader children may change safe-area layout, but cannot relocate the hovering book")
        let visible = cover.layer.presentation()?.frame ?? cover.frame
        await loading.prepareOpening()
        #expect(abs(cover.frame.midX - visible.midX) < 0.75)
        #expect(abs(cover.frame.midY - visible.midY) < 0.75)
        let frozen = cover.frame
        for _ in 0..<3 {
            loading.view.setNeedsLayout()
            loading.view.layoutIfNeeded()
        }
        #expect(cover.frame == frozen, "Opening must use the last visible hover pose after all pending layouts")
        #expect(cover.layer.animation(forKey: "Sumi.Hover") == nil)
    }
}
