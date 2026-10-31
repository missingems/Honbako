#if SUMI
import UIKit

/// The whole reader viewport chooses the presentation. A landscape book's
/// individual leaves can be portrait-shaped, so their own bounds are not a pose.
struct SumiReaderPresentation {
    let pageSizing: ReaderPageSizing
    let usesDoublePages: Bool
    let usesCustomCurl: Bool

    static func resolve(viewport: CGSize, readingMode: ReadingMode, reduceMotion: Bool,
                        sizingOverride: ReaderPageSizing? = nil) -> Self {
        let landscape = viewport.width.isFinite && viewport.height.isFinite
            && viewport.width > 0 && viewport.height > 0 && viewport.width > viewport.height
        let horizontal = readingMode == .ltr || readingMode == .rtl
        // Ignore legacy Fill preferences and overrides in every device pose.
        return Self(pageSizing: .fit,
                    usesDoublePages: landscape && horizontal,
                    usesCustomCurl: landscape && horizontal && !reduceMotion)
    }

    /// Fixed phone cutouts cannot obscure the printed page. The background
    /// still extends edge to edge; home-indicator space does not shrink paper.
    static func contentFrame(in bounds: CGRect, safeAreaInsets: UIEdgeInsets, margin: CGFloat = 12,
                             avoidsDisplayCutout: Bool = false) -> CGRect {
        guard avoidsDisplayCutout else { return bounds }
        return bounds.inset(by: UIEdgeInsets(top: safeAreaInsets.top, left: safeAreaInsets.left,
            bottom: 0, right: safeAreaInsets.right))
    }
}
#endif
