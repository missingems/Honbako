#if SUMI
import CoreGraphics

/// Only the top overscroll participates in revealing Search. Ordinary library
/// scrolling always produces the same zero value, avoiding per-frame updates.
enum SumiSearchPull {
    static let revealDistance: CGFloat = 52

    static func distance(contentOffset: CGFloat, topInset: CGFloat) -> CGFloat {
        min(revealDistance, max(0, -(contentOffset + topInset)))
    }

    static func progress(distance: CGFloat) -> CGFloat {
        min(1, max(0, distance / revealDistance))
    }
}
#endif
