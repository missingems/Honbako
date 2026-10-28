#if SUMI
import SwiftUI

/// Portrait belongs to this accessory scene only. The inner reader continues
/// to support rotation and folding normally.
final class HonbakoCoverDisplayHostingController: UIHostingController<HonbakoCoverDisplayView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }
    override var shouldAutorotate: Bool { false }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}
#endif
