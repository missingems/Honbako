#if SUMI
import UIKit

enum SumiPreviewGeometry {
    /// Individual page previews have 3pt corners; the enclosing glass keeps its capsule.
    /// Extremely small surfaces never round beyond half an edge.
    static func radius(in bounds: CGRect) -> CGFloat {
        max(0, min(SumiScrubberMetrics.previewCornerRadius, min(bounds.width, bounds.height) / 2))
    }

    static func outerCorners(leaf: Int, count: Int) -> CACornerMask {
        guard count > 1 else {
            return [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        }
        return leaf == 0 ? [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            : [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
    }
}
#endif
