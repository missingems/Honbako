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

    /// Paper is full bleed. The independently placed reader controls respect
    /// safe areas and reserved regions without changing this media viewport.
    static func contentFrame(in bounds: CGRect, safeAreaInsets: UIEdgeInsets, margin: CGFloat = 12) -> CGRect {
        bounds
    }
}
#endif
