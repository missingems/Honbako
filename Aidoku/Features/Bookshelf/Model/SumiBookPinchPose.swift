#if SUMI
import CoreGraphics

/// The normal single-cover close happens at the centre before returning to its slot.
/// A pure progress path lets an interrupted pinch reopen along the same route.
struct SumiBookPinchPose {
    let fold: CGFloat
    let coverOpacity: CGFloat
    let spreadFrame: CGRect
    let coverFrame: CGRect

    init(progress: CGFloat, origin: CGRect, viewport: CGRect) {
        let closing = 1 - min(1, max(0, progress))
        fold = min(1, closing / 0.68)
        coverOpacity = min(1, max(0, (fold - 0.78) / 0.22))
        let height = max(1, min(viewport.height * 0.62, viewport.width * 0.72 / max(0.1, origin.width / max(1, origin.height))))
        let centered = CGRect(x: viewport.midX - height * origin.width / max(1, origin.height) / 2,
            y: viewport.midY - height / 2, width: height * origin.width / max(1, origin.height), height: height)
        let travel = max(0, (closing - 0.68) / 0.32)
        let width = centered.width * pow(max(1, origin.width) / centered.width, travel)
        let coverHeight = centered.height * pow(max(1, origin.height) / centered.height, travel)
        let center = CGPoint(x: centered.midX + (origin.midX - centered.midX) * travel,
            y: centered.midY + (origin.midY - centered.midY) * travel)
        coverFrame = CGRect(x: center.x - width / 2, y: center.y - coverHeight / 2, width: width, height: coverHeight)
        let spreadHeight = viewport.height + (height - viewport.height) * fold
        let spreadWidth = viewport.width * spreadHeight / max(1, viewport.height)
        spreadFrame = CGRect(x: viewport.midX - spreadWidth / 2, y: viewport.midY - spreadHeight / 2,
            width: spreadWidth, height: spreadHeight)
    }
}
#endif
