#if SUMI
import UIKit

/// Keeps a hovering spread and its badge inside the reader's current hardware
/// region, including resized windows and a partially folded display.
enum SumiScrubberOverlayLayout {
    /// All inputs use the floating overlay's coordinate space, including when
    /// the native toolbar and the reader have different view ancestors.
    static func preferredFrame(size: CGSize, anchor: CGRect, axis: NSLayoutConstraint.Axis,
                               sidebarEdge: UIRectEdge, gap: CGFloat) -> CGRect {
        if axis == .vertical {
            return CGRect(x: sidebarEdge == .left ? anchor.maxX + gap : anchor.minX - gap - size.width,
                y: anchor.midY - size.height / 2, width: size.width, height: size.height)
        }
        return CGRect(x: anchor.midX - size.width / 2, y: anchor.minY - gap - size.height,
            width: size.width, height: size.height)
    }

    static func frame(_ preferred: CGRect, anchor: CGRect, in bounds: CGRect,
                      avoiding exclusions: [CGRect], preservesAspect: Bool) -> CGRect {
        guard !preferred.isEmpty, !bounds.isEmpty else { return preferred }
        let regions = ReaderControlLayout.availableRegions(in: bounds, avoiding: exclusions)
        let candidates = regions.filter { $0.width > 0 && $0.height > 0 }.map { region -> (CGRect, CGFloat, CGFloat) in
            let size: CGSize
            if preservesAspect {
                let scale = min(1, region.width / preferred.width, region.height / preferred.height)
                size = CGSize(width: preferred.width * scale, height: preferred.height * scale)
            } else {
                size = CGSize(width: min(preferred.width, region.width), height: min(preferred.height, region.height))
            }
            // Scaling changes both edges. Preserve the intended center before
            // clamping, rather than pinning a smaller print to its old origin.
            let fitted = CGRect(x: min(max(preferred.midX - size.width / 2, region.minX), region.maxX - size.width),
                                y: min(max(preferred.midY - size.height / 2, region.minY), region.maxY - size.height),
                                width: size.width, height: size.height)
            let nearest = CGPoint(x: min(max(anchor.midX, region.minX), region.maxX),
                                  y: min(max(anchor.midY, region.minY), region.maxY))
            let distance = pow(nearest.x - anchor.midX, 2) + pow(nearest.y - anchor.midY, 2)
            let displacement = pow(fitted.midX - preferred.midX, 2) + pow(fitted.midY - preferred.midY, 2)
            return (fitted, distance, displacement)
        }
        return candidates.min { lhs, rhs in
            if abs(lhs.1 - rhs.1) > 1 { return lhs.1 < rhs.1 }
            if abs(lhs.0.width * lhs.0.height - rhs.0.width * rhs.0.height) > 1 {
                return lhs.0.width * lhs.0.height > rhs.0.width * rhs.0.height
            }
            return lhs.2 < rhs.2
        }?.0 ?? CGRect(origin: bounds.origin, size: .zero)
    }
}
#endif
