#if SUMI
import UIKit

@MainActor
enum SumiReaderGesturePolicy {
    /// One finger reads the page; two fingers belong to the book dismissal.
    /// Apply this to every native pager replacement as well as vertical readers.
    static func reservePinches(in view: UIView) {
        for pan in (view.gestureRecognizers ?? []).compactMap({ $0 as? UIPanGestureRecognizer }) {
            pan.maximumNumberOfTouches = 1
        }
        view.subviews.forEach { reservePinches(in: $0) }
    }
}
#endif
