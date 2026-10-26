#if SUMI
import UIKit

/// The paper remains present while its print is fetched. Its first visible
/// image fades over this surface; already prepared pages appear fully printed.
final class SumiPageImageLoadingView: UIView {
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()
    private var revealAnimator: UIViewPropertyAnimator?
    private var generation = 0
    private(set) var isRevealing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = SumiPaperSurface.backgroundColor
        isUserInteractionEnabled = false
        accessibilityIdentifier = "Sumi.Reader.Page.Loading"
        isAccessibilityElement = true
        accessibilityLabel = "Loading page"
        label.text = "Loading page"
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .darkGray
        spinner.color = .darkGray
        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        ])
        spinner.startAnimating()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        generation += 1
        revealAnimator?.stopAnimation(true)
        revealAnimator = nil
        isRevealing = false
        isHidden = false
        spinner.startAnimating()
    }

    func reveal(_ imageView: UIImageView, animated: Bool, completion: (() -> Void)? = nil) {
        guard imageView.image != nil else { show(); completion?(); return }
        generation += 1
        let identity = generation
        revealAnimator?.stopAnimation(true)
        revealAnimator = nil
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            isRevealing = false
            imageView.alpha = 1
            isHidden = true
            spinner.stopAnimating()
            completion?()
            return
        }
        isHidden = false
        isRevealing = true
        imageView.alpha = 0
        let animator = UIViewPropertyAnimator(duration: 0.22, curve: .easeInOut) {
            imageView.alpha = 1
        }
        animator.addCompletion { [weak self] _ in
            guard let self, generation == identity else { return }
            isRevealing = false
            isHidden = true
            spinner.stopAnimating()
            revealAnimator = nil
            completion?()
        }
        revealAnimator = animator
        animator.startAnimation()
    }
}
#endif
