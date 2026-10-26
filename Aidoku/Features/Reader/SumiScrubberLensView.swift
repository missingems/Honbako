#if SUMI
import UIKit

final class SumiScrubberLensView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false; isAccessibilityElement = true; accessibilityTraits = .image
        // The center remains an accessibility anchor for the selected page;
        // selection adds neither magnification nor a decorative ring.
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
#endif
