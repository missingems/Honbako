#if SUMI
import UIKit

/// The native toolbar remains horizontal locally; the whole bar can stand on
/// its side while this host preserves the scrubber's physical axis and artwork.
final class SumiReaderToolbarScrubberHost: UIView {
    weak var scrubber: SumiPageScrubber?
    var axis: NSLayoutConstraint.Axis = .horizontal {
        didSet {
            guard axis != oldValue else { return }
            scrubber?.axis = axis
            setNeedsLayout()
        }
    }
    var idealLength: CGFloat = 300 {
        didSet {
            guard idealLength != oldValue else { return }
            invalidateIntrinsicContentSize()
            bounds.size = intrinsicContentSize
            setNeedsLayout()
        }
    }
    override var intrinsicContentSize: CGSize { CGSize(width: idealLength, height: 48) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.frame.size = intrinsicContentSize
        backgroundColor = .clear
        clipsToBounds = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func mount(_ scrubber: SumiPageScrubber) {
        self.scrubber = scrubber
        scrubber.axis = axis
        if scrubber.superview !== self { addSubview(scrubber) }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let scrubber else { return }
        let vertical = axis == .vertical
        scrubber.bounds = CGRect(origin: .zero, size: vertical
            ? CGSize(width: 48, height: bounds.width) : bounds.size)
        scrubber.transform = vertical ? CGAffineTransform(rotationAngle: -.pi / 2) : .identity
        scrubber.center = CGPoint(x: bounds.midX, y: bounds.midY)
        scrubber.setNeedsLayout()
        scrubber.layoutIfNeeded()
    }
}
#endif
