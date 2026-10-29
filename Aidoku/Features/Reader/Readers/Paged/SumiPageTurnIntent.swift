#if SUMI
import CoreGraphics

/// Travel belongs to one leaf. A short purposeful flick should finish, while
/// a deliberate reverse motion can still put the page back down.
enum SumiPageTurnIntent {
    static func shouldComplete(progress: CGFloat, velocity: CGFloat, distance: CGFloat, translation: CGFloat? = nil) -> Bool {
        let travel = max(0, translation ?? (max(0, progress) * max(1, distance)))
        guard travel >= min(32, max(12, distance * 0.1)) else { return false }
        if velocity < -140, progress < 0.8 { return false }
        if velocity > 220, travel >= 16 { return true }
        let threshold = min(64, max(28, distance * 0.18))
        return travel + max(0, velocity) * 0.16 >= threshold
    }
}
#endif
