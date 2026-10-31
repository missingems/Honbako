#if SUMI
import SwiftUI

/// The accessory accepts scene rotation while its print counter-rotates to portrait.
final class HonbakoCoverDisplayHostingController: UIHostingController<HonbakoCoverDisplayView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }
    override var shouldAutorotate: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}
#endif
