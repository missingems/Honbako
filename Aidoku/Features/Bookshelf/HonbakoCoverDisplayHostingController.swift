#if SUMI
import SwiftUI

/// The cover follows its own scene orientation and crops to fill the display.
final class HonbakoCoverDisplayHostingController: UIHostingController<HonbakoCoverDisplayView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }
    override var shouldAutorotate: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}
#endif
