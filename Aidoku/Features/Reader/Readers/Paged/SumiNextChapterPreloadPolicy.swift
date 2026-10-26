#if SUMI
import Foundation

enum SumiNextChapterPreloadPolicy {
    static let remainingPages = 3
    static let firstPages = 3
    static let retryDelay: TimeInterval = 5

    static func shouldPrepare(page: Int, total: Int, visibleCount: Int = 1) -> Bool {
        guard total > 0, page > 0 else { return false }
        let lastVisible = min(total, page + max(1, visibleCount) - 1)
        return total - lastVisible <= remainingPages
    }
}
#endif
