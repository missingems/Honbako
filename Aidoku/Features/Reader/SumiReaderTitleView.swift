#if SUMI
import UIKit

/// A transient book title follows the reader controls without becoming a bar.
final class SumiReaderTitleView: UIView {
    private let surface = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
    private let label = UILabel()
    private var visibilityAnimator: UIViewPropertyAnimator?
    private var visibilityIdentity = UUID()
    private(set) var isVisible = false

    init(title: String) {
        super.init(frame: .zero)
        accessibilityIdentifier = "Sumi.Reader.Title"
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .header
        surface.clipsToBounds = true
        surface.layer.cornerCurve = .continuous
        surface.layer.cornerRadius = 13
        surface.contentView.backgroundColor = UIColor(white: 0.08, alpha: 0.72)
        addSubview(surface)
        label.text = title
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.isAccessibilityElement = false
        surface.contentView.addSubview(label)
        alpha = 0
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func preferredSize(availableWidth: CGFloat) -> CGSize {
        let width = max(1, min(480, availableWidth))
        let size = label.sizeThatFits(CGSize(width: max(1, width - 24), height: .greatestFiniteMagnitude))
        return CGSize(width: min(width, size.width + 24), height: size.height + 16)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        surface.frame = bounds
        label.frame = surface.bounds.insetBy(dx: 12, dy: 8)
    }

    func setVisible(_ visible: Bool, animated: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        visibilityIdentity = UUID()
        let identity = visibilityIdentity
        visibilityAnimator?.stopAnimation(true)
        visibilityAnimator = nil
        if visible { isHidden = false }
        let changes = {
            self.alpha = visible ? 1 : 0
            self.surface.effect = visible ? UIBlurEffect(style: .systemThickMaterialDark) : nil
        }
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            changes()
            isHidden = !visible
            return
        }
        let animator = UIViewPropertyAnimator(duration: visible ? 0.28 : 0.20, curve: .easeInOut, animations: changes)
        animator.addCompletion { [weak self] _ in
            guard let self, visibilityIdentity == identity else { return }
            isHidden = !visible
            visibilityAnimator = nil
        }
        visibilityAnimator = animator
        animator.startAnimation()
    }
}
#endif
