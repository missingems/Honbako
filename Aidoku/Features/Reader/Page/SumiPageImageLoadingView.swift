#if SUMI
import UIKit

/// One paper surface owns loading, failure and reveal, so a retry action can
/// never sit on top of an unrelated spinner or stale loading message.
final class SumiPageImageLoadingView: UIView {
    enum State: Equatable { case loading, failed, revealing, hidden }

    private let spinner = UIActivityIndicatorView(style: .medium)
    private let symbol = UIImageView(image: UIImage(systemName: "photo.badge.exclamationmark"))
    private let label = UILabel()
    private let detailLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let contentStack = UIStackView()
    private var onRetry: (() -> Void)?
    private var revealAnimator: UIViewPropertyAnimator?
    private var generation = 0
    private var contentViewport: CGRect?
    private(set) var state: State = .loading
    var isRevealing: Bool { state == .revealing }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = SumiPaperSurface.backgroundColor
        // Reader paper is always light, including when app chrome is dark.
        // Resolve standard text and action colors against that paper surface.
        overrideUserInterfaceStyle = .light
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 0
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        spinner.color = .secondaryLabel
        spinner.isAccessibilityElement = false
        spinner.hidesWhenStopped = true
        symbol.tintColor = .secondaryLabel
        symbol.contentMode = .scaleAspectFit
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: .preferredFont(forTextStyle: .title2))
        symbol.isAccessibilityElement = false
        var configuration = UIButton.Configuration.tinted()
        configuration.title = String(localized: "Try Again")
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .init(top: 12, leading: 20, bottom: 12, trailing: 20)
        retryButton.configuration = configuration
        retryButton.tintColor = HonbakoPalette.accentUIColor
        retryButton.titleLabel?.adjustsFontForContentSizeCategory = true
        retryButton.accessibilityIdentifier = "Sumi.Reader.Page.Retry"
        retryButton.addAction(UIAction { [weak self] _ in
            guard let self, state == .failed, let onRetry else { return }
            show()
            onRetry()
        }, for: .touchUpInside)
        let stack = contentStack
        [spinner, symbol, label, detailLabel, retryButton].forEach { stack.addArrangedSubview($0) }
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 340),
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        show()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateContentCenter()
    }

    /// A scrolling page can be much taller than the window. Keep status
    /// controls in its visible portion without resizing the canonical page.
    func updateContentViewport(_ viewport: CGRect?) {
        contentViewport = viewport
        updateContentCenter()
    }

    private func updateContentCenter() {
        let visible = contentViewport.map { bounds.intersection($0) } ?? bounds
        guard !visible.isNull, !visible.isInfinite, !visible.isEmpty else { return }
        let transform = CGAffineTransform(translationX: visible.midX - bounds.midX,
            y: visible.midY - bounds.midY)
        guard contentStack.transform != transform else { return }
        UIView.performWithoutAnimation { contentStack.transform = transform }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard state == .failed, !isHidden, alpha > 0.01 else { return nil }
        // The paper still passes page-turn and close gestures through. Only
        // the native retry control claims a touch.
        return retryButton.hitTest(retryButton.convert(point, from: self), with: event)
    }

    private func cancelReveal() {
        generation += 1
        revealAnimator?.stopAnimation(true)
        revealAnimator = nil
    }

    func show() {
        cancelReveal()
        state = .loading
        onRetry = nil
        accessibilityIdentifier = "Sumi.Reader.Page.Loading"
        label.text = String(localized: "Loading page")
        label.font = .preferredFont(forTextStyle: .footnote)
        label.isHidden = false
        detailLabel.isHidden = true
        symbol.isHidden = true
        retryButton.isHidden = true
        isUserInteractionEnabled = false
        isHidden = false
        spinner.startAnimating()
    }

    func showFailure(retry: @escaping () -> Void) {
        cancelReveal()
        state = .failed
        onRetry = retry
        accessibilityIdentifier = "Sumi.Reader.Page.Error"
        spinner.stopAnimating()
        label.text = String(localized: "Couldn’t Load Page")
        label.font = .preferredFont(forTextStyle: .headline)
        label.isHidden = false
        detailLabel.text = String(localized: "Try again, or turn the page to keep reading.")
        detailLabel.isHidden = false
        symbol.isHidden = false
        retryButton.isHidden = false
        isUserInteractionEnabled = true
        isHidden = false
    }

    func hide() {
        cancelReveal()
        state = .hidden
        onRetry = nil
        spinner.stopAnimating()
        isHidden = true
        isUserInteractionEnabled = false
    }

    func reveal(_ imageView: UIImageView, animated: Bool, completion: (() -> Void)? = nil) {
        guard imageView.image != nil else { show(); completion?(); return }
        cancelReveal()
        let identity = generation
        onRetry = nil
        spinner.stopAnimating()
        label.isHidden = true
        detailLabel.isHidden = true
        symbol.isHidden = true
        retryButton.isHidden = true
        isUserInteractionEnabled = false
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            state = .hidden
            imageView.alpha = 1
            isHidden = true
            completion?()
            return
        }
        isHidden = false
        state = .revealing
        imageView.alpha = 0
        let animator = UIViewPropertyAnimator(duration: 0.22, curve: .easeInOut) {
            imageView.alpha = 1
        }
        animator.addCompletion { [weak self] _ in
            guard let self, generation == identity else { return }
            state = .hidden
            isHidden = true
            revealAnimator = nil
            completion?()
        }
        revealAnimator = animator
        animator.startAnimation()
    }
}
#endif
