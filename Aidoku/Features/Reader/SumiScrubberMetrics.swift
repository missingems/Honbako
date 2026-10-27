#if SUMI
import UIKit

enum SumiScrubberMetrics {
    static let toolbarThickness: CGFloat = 48
    static let railThickness: CGFloat = 40
    static let cornerRadius: CGFloat = 13
    static let previewCornerRadius: CGFloat = 8
    static let previewGap: CGFloat = 4
    static let pageHeight: CGFloat = 32
    static let pageAspect: CGFloat = 0.7
    static let badgeGap: CGFloat = 4
    static let hoverGap: CGFloat = 12

    static func hoverHeight(in available: CGSize) -> CGFloat {
        min(300, max(180, available.height * 0.4))
    }

    static func cellPitch(axis: NSLayoutConstraint.Axis, usesPairedPages: Bool) -> CGFloat {
        let count: CGFloat = usesPairedPages ? 2 : 1
        let width = pageHeight * pageAspect * count
        if axis == .vertical {
            let crossLength = railThickness - 8
            let height = pageHeight * min(1, crossLength / width)
            return ceil(height + previewGap)
        }
        return ceil(width + previewGap)
    }
}
#endif
