#if SUMI
import UIKit

/// Once two fingers commit to the book, its page and filmstrip stop tracking.
/// Only enabled, reader-owned pans are restored; window/system gestures stay live.
@MainActor
final class SumiBookPanSuspension {
    private var pans: [UIPanGestureRecognizer] = []
    private var identities: Set<ObjectIdentifier> = []

    func suspend(in roots: [UIView], includingAncestorsOf anchors: [UIView] = [],
                 excluding excluded: UIGestureRecognizer? = nil) {
        var visited: Set<ObjectIdentifier> = []
        func visit(_ view: UIView, descend: Bool) {
            guard !(view is UIWindow), visited.insert(ObjectIdentifier(view)).inserted else { return }
            for pan in (view.gestureRecognizers ?? []).compactMap({ $0 as? UIPanGestureRecognizer })
                where pan !== excluded && pan.isEnabled && identities.insert(ObjectIdentifier(pan)).inserted {
                pans.append(pan)
                pan.isEnabled = false
            }
            if descend { view.subviews.forEach { visit($0, descend: true) } }
        }
        roots.forEach { visit($0, descend: true) }
        for anchor in anchors {
            var ancestor = anchor.superview
            while let view = ancestor, !(view is UIWindow) {
                visit(view, descend: false)
                ancestor = view.superview
            }
        }
    }

    func restore() {
        let suspended = pans
        pans = []
        identities = []
        suspended.forEach { $0.isEnabled = true }
    }
}
#endif
