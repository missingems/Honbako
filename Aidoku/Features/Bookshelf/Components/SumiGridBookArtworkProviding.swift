#if SUMI
import UIKit

/// Raw print and physical pose remain separate from the rendered source image.
/// A transition must never put an already lit 3D snapshot onto another 3D cover.
@MainActor
protocol SumiGridBookArtworkProviding: AnyObject {
    var coverArtwork: UIImage? { get }
    var bookPose: SumiGridBookPose { get }
    var renderedBookPose: SumiGridBookPose? { get }
    func beginBookTransition()
    func endBookTransition()
}

extension SumiGridBookArtworkProviding {
    var renderedBookPose: SumiGridBookPose? { bookPose }
    func beginBookTransition() {}
    func endBookTransition() {}
}
#endif
