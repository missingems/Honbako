#if SUMI
import UIKit

/// The system may transfer a presented reader between display windows without
/// recreating its controller. Keep its window-scoped gesture on that window.
final class SumiBookGestureHostObserver: UIView {
    var windowDidChange: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        windowDidChange?()
    }
}
#endif
