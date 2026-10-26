import UIKit

/// Native center curl displays two independently scrollable physical leaves.
/// Explicit single-page layouts retain the ordinary edge-spine contract.
struct ReaderPageTransition: Equatable {
    let style: UIPageViewController.TransitionStyle
    let orientation: UIPageViewController.NavigationOrientation
    let spine: UIPageViewController.SpineLocation

    static func resolve(viewport: CGSize, readingMode: ReadingMode, reduceMotion: Bool, paired: Bool = true) -> Self {
        let horizontal = readingMode == .ltr || readingMode == .rtl
        let landscape = viewport.width.isFinite && viewport.height.isFinite
            && viewport.width > 0 && viewport.height > 0 && viewport.width > viewport.height
        let curls = horizontal && landscape && !reduceMotion
        return Self(
            style: curls ? .pageCurl : .scroll,
            orientation: readingMode == .vertical ? .vertical : .horizontal,
            spine: curls ? (paired ? .mid : (readingMode == .rtl ? .max : .min)) : .none
        )
    }

    func matches(_ controller: UIPageViewController) -> Bool {
        controller.transitionStyle == style && controller.navigationOrientation == orientation
            && controller.spineLocation == spine
    }

    func makeController() -> UIPageViewController {
        let options: [UIPageViewController.OptionsKey: Any]? = style == .pageCurl
            ? [.spineLocation: NSNumber(value: spine.rawValue)] : nil
        let controller = UIPageViewController(transitionStyle: style, navigationOrientation: orientation, options: options)
        controller.isDoubleSided = spine == .mid
        return controller
    }
}
