#if SUMI
import UIKit

/// Resume the tabletop after its book presentation actually leaves the screen.
/// A full-screen reader above this controller must keep the library paused.
final class SumiBookNavigationController: NavigationController {
    var onBookDismissed: (() -> Void)?

    override var childForStatusBarHidden: UIViewController? { topViewController }
    override var childForStatusBarStyle: UIViewController? { topViewController }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if presentingViewController == nil {
            finishDismissal()
        }
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        let dismissesBook = presentedViewController == nil
        super.dismiss(animated: flag) { [weak self] in
            if dismissesBook, self?.presentingViewController == nil { self?.finishDismissal() }
            completion?()
        }
    }

    private func finishDismissal() {
        let action = onBookDismissed
        onBookDismissed = nil
        action?()
    }
}
#endif
