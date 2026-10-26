#if SUMI
import AidokuRunner
import UIKit

/// A quiet paper surface between chapters. The reader's next normal page turn
/// continues into the adjacent chapter; only a failed load needs an action.
final class SumiChapterBoundaryView: UIView {
    let titleLabel = UILabel()
    let detailLabel = UILabel()
    let continueButton = UIButton(type: .system)
    private let progress = UIActivityIndicatorView(style: .large)
    var onContinue: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = SumiPaperSurface.backgroundColor
        accessibilityIdentifier = "Sumi.Reader.ChapterBoundary"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .black
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .darkGray
        detailLabel.numberOfLines = 0
        detailLabel.textAlignment = .center
        var configuration = UIButton.Configuration.tinted()
        configuration.baseForegroundColor = .black
        configuration.baseBackgroundColor = .lightGray
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .init(top: 12, leading: 20, bottom: 12, trailing: 20)
        continueButton.configuration = configuration
        continueButton.titleLabel?.adjustsFontForContentSizeCategory = true
        continueButton.accessibilityIdentifier = "Sumi.Reader.ContinueChapter"
        continueButton.addAction(UIAction { [weak self] _ in self?.onContinue?() }, for: .touchUpInside)
        progress.color = .darkGray
        progress.hidesWhenStopped = true
        let stack = UIStackView(arrangedSubviews: [progress, titleLabel, detailLabel, continueButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.setCustomSpacing(24, after: detailLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            continueButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showLoading() {
        titleLabel.text = "Loading Chapter"
        detailLabel.text = nil
        detailLabel.isHidden = true
        continueButton.isHidden = true
        onContinue = nil
        progress.startAnimating()
    }

    func showError(retry: @escaping () -> Void) {
        progress.stopAnimating()
        titleLabel.text = "Chapter Unavailable"
        detailLabel.text = "This chapter couldn’t be loaded. Try again."
        detailLabel.isHidden = false
        continueButton.configuration?.title = "Try Again"
        continueButton.isHidden = false
        onContinue = retry
    }

    func update(type: ReaderInfoPageType, destination: AidokuRunner.Chapter?) {
        progress.stopAnimating()
        titleLabel.text = type == .previous && destination == nil ? "The Beginning" : "Chapter End"
        detailLabel.text = nil
        detailLabel.isHidden = true
        continueButton.configuration?.title = nil
        continueButton.isHidden = true
        onContinue = nil
    }
}
#endif
