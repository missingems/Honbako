#if SUMI
import CoreGraphics
import Foundation

/// Travel belongs to one leaf. A short purposeful flick should finish, while
/// a deliberate reverse motion can still put the page back down.
enum SumiPageTurnIntent {
    static func shouldComplete(progress: CGFloat, velocity: CGFloat, distance: CGFloat, translation: CGFloat? = nil) -> Bool {
        let travel = max(0, translation ?? (max(0, progress) * max(1, distance)))
        guard travel >= min(16, max(10, distance * 0.05)) else { return false }
        if velocity < -140, progress < 0.8 { return false }
        if velocity > 180, travel >= 12 { return true }
        let threshold = min(36, max(20, distance * 0.1))
        return travel + max(0, velocity) * 0.16 >= threshold
    }

    /// A released leaf clears the next gesture quickly without shortening a
    /// toolbar turn or the scrubber's complete journey through several leaves.
    static func releaseDuration(remaining: CGFloat, velocity: CGFloat) -> TimeInterval {
        max(0.12, min(0.36, Double(remaining) * 0.32 - min(abs(Double(velocity)) / 18000, 0.10)))
    }
}
#endif
