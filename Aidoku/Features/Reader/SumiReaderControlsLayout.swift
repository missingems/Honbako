#if SUMI
import UIKit

enum SumiReaderControlsLayout {
    /// Portrait uses one centered bottom strip, including the open inner
    /// canvas. Tapped-leaf placement applies only to an actual landscape view.
    static func bottomSide(in bounds: CGRect, isTablet: Bool, requestedSide: UIRectEdge?) -> UIRectEdge? {
        !isTablet && bounds.width > bounds.height ? (requestedSide ?? .right) : nil
    }

    static func sidebarEdge(systemEdge: UIRectEdge?, hasInnerFold: Bool) -> UIRectEdge? {
        hasInnerFold ? nil : systemEdge
    }
    static func toolbarInsets(_ safeAreaInsets: UIEdgeInsets, systemUsesSideBars: Bool,
                              ignoresSideInsets: Bool = false) -> UIEdgeInsets {
        guard systemUsesSideBars || ignoresSideInsets else { return safeAreaInsets }
        var insets = safeAreaInsets
        insets.left = 0
        insets.right = 0
        return insets
    }

    /// The system's vertical bar preference takes priority. Otherwise a bottom
    /// strip belongs to the tapped landscape leaf or the whole portrait screen.
    static func toolbarFrame(in bounds: CGRect, safeAreaInsets: UIEdgeInsets, avoiding exclusions: [CGRect],
                             side: UIRectEdge?, size: CGSize, axis: NSLayoutConstraint.Axis = .horizontal) -> CGRect {
        let safe = bounds.inset(by: UIEdgeInsets(top: max(8, safeAreaInsets.top),
            left: max(8, safeAreaInsets.left), bottom: max(8, safeAreaInsets.bottom + 4),
            right: max(8, safeAreaInsets.right)))
        if axis == .vertical {
            return sidebarFrame(in: safe, avoiding: exclusions, side: side ?? .right, size: size)
        }
        let preferred: CGRect
        if let side {
            let half = CGRect(x: side == .left ? bounds.minX : bounds.midX, y: bounds.minY,
                              width: bounds.width / 2, height: bounds.height).insetBy(dx: 8, dy: 0)
            preferred = safe.intersection(half)
        } else { preferred = safe }
        func regions(in region: CGRect) -> [CGRect] {
            guard !region.isNull else { return [] }
            return ReaderControlLayout.availableRegions(in: region, avoiding: exclusions)
                .filter { $0.width >= 156 && $0.height >= 48 }
        }
        let preferredRegions = regions(in: preferred)
        let candidates = preferredRegions.isEmpty ? regions(in: safe) : preferredRegions
        let center = side != nil && !preferred.isNull ? preferred.midX : bounds.midX
        if let region = candidates.min(by: { lhs, rhs in
            let left = (safe.maxY - lhs.maxY) * 4 + abs(lhs.midX - center)
            let right = (safe.maxY - rhs.maxY) * 4 + abs(rhs.midX - center)
            if abs(left - right) > 0.5 { return left < right }
            return lhs.width * lhs.height > rhs.width * rhs.height
        }) {
            let width = min(size.width, region.width)
            let height = min(size.height, region.height)
            return CGRect(x: min(max(center - width / 2, region.minX), region.maxX - width),
                          y: region.maxY - height, width: width, height: height)
        }
        let width = max(1, min(size.width, safe.width))
        let height = max(1, min(size.height, safe.height))
        return CGRect(x: safe.midX - width / 2, y: safe.maxY - height, width: width, height: height)
    }

    private static func sidebarFrame(in safe: CGRect, avoiding exclusions: [CGRect],
                                     side: UIRectEdge, size: CGSize) -> CGRect {
        let regions = ReaderControlLayout.availableRegions(in: safe, avoiding: exclusions)
            .filter { $0.width > 0 && $0.height > 0 }
        let fitting = regions.filter { $0.width >= min(48, size.width) && $0.height >= min(156, size.height) }
        let candidates = fitting.isEmpty ? regions : fitting
        let region = candidates.min { lhs, rhs in
            let leftDistance = side == .left ? lhs.minX - safe.minX : safe.maxX - lhs.maxX
            let rightDistance = side == .left ? rhs.minX - safe.minX : safe.maxX - rhs.maxX
            let leftScore = leftDistance * 4 + abs(lhs.midY - safe.midY)
            let rightScore = rightDistance * 4 + abs(rhs.midY - safe.midY)
            if abs(leftScore - rightScore) > 0.5 { return leftScore < rightScore }
            return lhs.height > rhs.height
        } ?? safe
        let width = max(1, min(size.width, region.width))
        let height = max(1, min(size.height, region.height))
        return CGRect(x: side == .left ? region.minX : region.maxX - width,
            y: min(max(safe.midY - height / 2, region.minY), region.maxY - height), width: width, height: height)
    }
}
#endif
