#if SUMI
import CoreGraphics
import UIKit

/// Undo only this accessory scene's UI rotation. The print stays aligned with
/// the physical portrait cover while the reading scene may rotate freely.
struct HonbakoCoverDisplayPose: Equatable {
    let rotation: Double
    let swapsAxes: Bool

    init(orientation: UIInterfaceOrientation) {
        switch orientation {
        case .landscapeLeft:
            rotation = .pi / 2; swapsAxes = true
        case .landscapeRight:
            rotation = -.pi / 2; swapsAxes = true
        case .portraitUpsideDown:
            rotation = .pi; swapsAxes = false
        default:
            rotation = 0; swapsAxes = false
        }
    }

    func printSize(in viewport: CGSize) -> CGSize {
        swapsAxes ? CGSize(width: viewport.height, height: viewport.width) : viewport
    }
}
#endif
