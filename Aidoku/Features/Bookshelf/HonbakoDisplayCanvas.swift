#if SUMI
import UIKit

/// The Duo's reserved canvas and side bars manage their own occlusions.
/// Regular phones keep artwork clear of their fixed display cutout.
enum HonbakoDisplayCanvas {
    static func usesReservedCanvas(in view: UIView) -> Bool {
        guard #available(iOS 27.1, *) else { return false }
        let edge = view.traitCollection.verticalBarEdge
        return edge == .leading || edge == .trailing
            || !view.reservedRegions(kind: .division, options: .includeInactive).isEmpty
    }

    static func avoidsDisplayCutout(in view: UIView) -> Bool {
        view.traitCollection.userInterfaceIdiom == .phone && !usesReservedCanvas(in: view)
    }
}
#endif
