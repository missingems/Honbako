#if SUMI
import Nuke
import UIKit

/// The cache and every pickup/return surface share the same finished print.
struct HonbakoCoverMaterialProcessor: ImageProcessing, Hashable, Sendable {
    var identifier: String { "com.missingems.honbako.cover-material.v1" }

    func process(_ image: UIImage) -> UIImage? {
        HonbakoCoverMetalRenderer.shared?.render(image) ?? image
    }
}
#endif
