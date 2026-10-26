#if SUMI
import UIKit

/// Keeps a hovering spread and its badge inside the reader's current hardware
/// region, including resized windows and a partially folded display.
enum SumiScrubberOverlayLayout {
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
            let fitted = CGRect(x: min(max(preferred.minX, region.minX), region.maxX - size.width),
                                y: min(max(preferred.minY, region.minY), region.maxY - size.height),
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
