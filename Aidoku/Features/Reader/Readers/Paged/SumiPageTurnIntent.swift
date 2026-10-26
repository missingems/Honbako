#if SUMI
import CoreGraphics

/// Travel belongs to one leaf. A short purposeful flick should finish, while
/// a deliberate reverse motion can still put the page back down.
enum SumiPageTurnIntent {
    static func shouldComplete(progress: CGFloat, velocity: CGFloat, distance: CGFloat) -> Bool {
        let travel = max(0, progress) * max(1, distance)
        guard travel >= 10 else { return false }
        if velocity < -140, progress < 0.8 { return false }
        if velocity > 220, travel >= 16 { return true }
        return progress + max(0, velocity) / max(1, distance) * 0.16 >= 0.28
    }
}
#endif
