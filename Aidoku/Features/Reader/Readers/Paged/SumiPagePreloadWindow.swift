#if SUMI
import Foundation

/// Keep a small decoded neighborhood warm in reading order. Disk caching and
/// Nuke still coalesce shared requests; long chapters do not retain every leaf.
enum SumiPagePreloadWindow {
    static let ahead = 6
    static let behind = 2

    static func range(around firstVisiblePage: Int, visibleCount: Int, total: Int) -> ClosedRange<Int>? {
        guard total > 0 else { return nil }
        let first = min(max(1, firstVisiblePage), total)
        return max(1, first - behind)...min(total, first + max(1, visibleCount) - 1 + ahead)
    }
}
#endif
