#if SUMI
import UIKit

enum SumiReaderTitleLayout {
    static func frame(in bounds: CGRect, safeAreaInsets: UIEdgeInsets, avoiding exclusions: [CGRect],
                      size: CGSize, side: UIRectEdge?) -> CGRect {
        let safe = bounds.inset(by: UIEdgeInsets(top: max(8, safeAreaInsets.top + 8),
            left: max(12, safeAreaInsets.left + 8), bottom: max(8, safeAreaInsets.bottom),
            right: max(12, safeAreaInsets.right + 8)))
        let preferredCenter: CGFloat
        if side == .left { preferredCenter = bounds.minX + bounds.width / 4 }
        else if side == .right { preferredCenter = bounds.maxX - bounds.width / 4 }
        else { preferredCenter = safe.midX }
        let regions = ReaderControlLayout.availableRegions(in: safe, avoiding: exclusions)
            .filter { $0.width >= 44 && $0.height >= size.height }
        let region = regions.min { lhs, rhs in
            let left = (lhs.minY - safe.minY) * 4 + abs(lhs.midX - preferredCenter)
            let right = (rhs.minY - safe.minY) * 4 + abs(rhs.midX - preferredCenter)
            return abs(left - right) > 0.5 ? left < right : lhs.width > rhs.width
        } ?? safe
        let width = max(1, min(size.width, region.width))
        let height = max(1, min(size.height, region.height))
        return CGRect(x: min(max(preferredCenter - width / 2, region.minX), region.maxX - width),
            y: region.minY, width: width, height: height)
    }
}
#endif
