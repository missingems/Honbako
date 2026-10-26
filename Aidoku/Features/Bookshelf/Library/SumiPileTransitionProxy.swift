#if SUMI
import SceneKit
import UIKit

/// The pose remains available even if a library refresh removes the source
/// node while its detail is presented. UIKit retains the visible image view.
struct SumiPileTransitionProxy {
    let bookID: String
    let pose: SCNNode
    let view: UIImageView
    let source: SumiBookTransitionSource
}
#endif
