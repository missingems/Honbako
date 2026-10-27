#if SUMI
import SwiftUI
import UIKit

/// A floating, unmodified cover carries its loading pill just below the book.
final class SumiReaderLoadingViewController: UIViewController, UIGestureRecognizerDelegate {
    let book: SumiBook
    var closeBook: (() -> Void)?
    var retry: (() -> Void)?
    private let snapshot: UIImage?
    private let canvasAspect: CGFloat
    private let dimming = UIView()
    private let cover = UIView()
    private let loadingPill = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let loadingLabel = UILabel()
    private let activity = UIActivityIndicatorView(style: .medium)
    private let message = UILabel()
    private let retryButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private var hasError = false
    private let status = UIStackView()
    private var isLifting = false
    private var hasLifted = false
    private var liftViewportSize: CGSize = .zero
    private var isPreparingOpening = false
    private var isReturningToLibrary = false
    var zoomSourceView: UIView { cover }

    init(book: SumiBook, snapshot: UIImage? = nil, canvasAspect: CGFloat = 0.68) {
        self.book = book
        self.snapshot = snapshot
        self.canvasAspect = canvasAspect
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancelFromKeyboard))]
    }
    @objc private func cancelFromKeyboard() { _ = accessibilityPerformEscape() }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "Sumi.Book.Loading"
        view.accessibilityViewIsModal = true
        let cancelAction = UIAccessibilityCustomAction(name: String(localized: "Cancel opening")) { [weak self] _ in
            self?.accessibilityPerformEscape() ?? false
        }
        view.accessibilityCustomActions = [cancelAction]
        let outsideTap = UITapGestureRecognizer(target: self, action: #selector(cancelOpeningFromTap(_:)))
        outsideTap.delegate = self
        outsideTap.cancelsTouchesInView = false
        view.addGestureRecognizer(outsideTap)
        dimming.backgroundColor = .black
        dimming.alpha = 0
        dimming.accessibilityIdentifier = "Sumi.Book.Dimming"
        dimming.isUserInteractionEnabled = true
        view.addSubview(dimming)
        cover.accessibilityIdentifier = "Sumi.Book.HoverCover"
        cover.isAccessibilityElement = false
        cover.accessibilityLabel = book.title
        cover.accessibilityValue = String(localized: "Loading")
        view.addSubview(cover)
        let artwork: UIView
        if let snapshot {
            let image = UIImageView(image: snapshot)
            image.contentMode = .scaleAspectFill
            artwork = image
        } else {
            let host = UIHostingController(rootView: BookCoverFace(book: book.presentation, showsBinding: false))
            addChild(host)
            artwork = host.view
            host.didMove(toParent: self)
        }
        artwork.backgroundColor = .clear
        artwork.frame = cover.bounds
        artwork.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        artwork.layer.cornerRadius = 0
        artwork.clipsToBounds = true
        cover.addSubview(artwork)
        message.font = .preferredFont(forTextStyle: .body)
        message.adjustsFontForContentSizeCategory = true
        message.numberOfLines = 0
        message.textColor = .white
        message.textAlignment = .center
        message.accessibilityIdentifier = "SumiReader.Error"
        message.accessibilityCustomActions = [cancelAction]
        retryButton.setTitle(String(localized: "Retry"), for: .normal)
        retryButton.tintColor = .white
        retryButton.addAction(UIAction { [weak self] _ in self?.retry?() }, for: .touchUpInside)
        closeButton.setTitle(String(localized: "Close"), for: .normal)
        closeButton.tintColor = .white
        closeButton.accessibilityIdentifier = "Sumi.Book.LoadingClose"
        closeButton.addAction(UIAction { [weak self] _ in self?.closeBook?() }, for: .touchUpInside)
        activity.color = .label
        activity.hidesWhenStopped = true
        activity.isAccessibilityElement = false
        activity.accessibilityIdentifier = "Sumi.Book.LoadingIndicator"
        activity.accessibilityLabel = String(localized: "Loading \(book.title)")
        activity.accessibilityCustomActions = [cancelAction]
        loadingLabel.text = String(localized: "Loading")
        loadingLabel.font = .preferredFont(forTextStyle: .subheadline)
        loadingLabel.adjustsFontForContentSizeCategory = true
        loadingLabel.textColor = .label
        loadingLabel.accessibilityIdentifier = "Sumi.Book.LoadingLabel"
        loadingLabel.isAccessibilityElement = false
        let loadingContent = UIStackView(arrangedSubviews: [activity, loadingLabel])
        loadingContent.axis = .horizontal
        loadingContent.alignment = .center
        loadingContent.spacing = 8
        loadingContent.translatesAutoresizingMaskIntoConstraints = false
        loadingPill.contentView.addSubview(loadingContent)
        NSLayoutConstraint.activate([
            loadingContent.leadingAnchor.constraint(equalTo: loadingPill.contentView.leadingAnchor, constant: 16),
            loadingContent.trailingAnchor.constraint(equalTo: loadingPill.contentView.trailingAnchor, constant: -16),
            loadingContent.topAnchor.constraint(equalTo: loadingPill.contentView.topAnchor, constant: 10),
            loadingContent.bottomAnchor.constraint(equalTo: loadingPill.contentView.bottomAnchor, constant: -10)
        ])
        loadingPill.clipsToBounds = true
        loadingPill.isUserInteractionEnabled = false
        loadingPill.isAccessibilityElement = true
        loadingPill.accessibilityIdentifier = "Sumi.Book.LoadingPill"
        loadingPill.accessibilityLabel = String(localized: "Loading \(book.title)")
        loadingPill.accessibilityCustomActions = [cancelAction]
        loadingPill.translatesAutoresizingMaskIntoConstraints = false
        loadingPill.layer.cornerCurve = .continuous
        loadingPill.layer.cornerRadius = 22
        cover.addSubview(loadingPill)
        NSLayoutConstraint.activate([
            loadingPill.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            loadingPill.topAnchor.constraint(equalTo: cover.bottomAnchor, constant: 16),
            loadingPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            loadingPill.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        status.axis = .vertical
        status.alignment = .center
        status.spacing = 12
        let errorActions = UIStackView(arrangedSubviews: [retryButton, closeButton])
        errorActions.axis = .horizontal
        errorActions.spacing = 28
        errorActions.alignment = .center
        [message, errorActions].forEach(status.addArrangedSubview)
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)
        NSLayoutConstraint.activate([
            status.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            status.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            status.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
        showLoading()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        dimming.frame = view.bounds
        // Child layout and safe-area updates during reader preparation must not
        // move a hovering book. Only a real viewport resize changes its target.
        if hasLifted, !isLifting, !isPreparingOpening, liftViewportSize != view.bounds.size {
            stopHovering()
            cover.layer.transform = CATransform3DIdentity
            cover.frame = openingCoverFrame()
            liftViewportSize = view.bounds.size
            startHovering()
        }
        layoutLoadingIndicator()
    }

    func beginLoading(from source: UIView?) {
        loadViewIfNeeded()
        view.layoutIfNeeded()
        guard !isReturningToLibrary else { return }
        isPreparingOpening = false
        liftViewportSize = view.bounds.size
        let target = openingCoverFrame()
        cover.layer.removeAnimation(forKey: "Sumi.Hover")
        cover.layer.transform = CATransform3DIdentity
        let sourceFrame = source.flatMap { $0.window == nil ? nil : $0.convert($0.bounds, to: view) }
        cover.frame = sourceFrame ?? target
        layoutLoadingIndicator()
        isLifting = true
        hasLifted = true
        becomeFirstResponder()
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.48,
                       delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.cover.frame = target
            self.cover.layoutIfNeeded()
            self.dimming.alpha = 0.68
        } completion: { [weak self] _ in
            guard let self, !self.isReturningToLibrary else { return }
            self.isLifting = false
            self.startHovering()
        }
    }

    private func layoutLoadingIndicator() {
        cover.layoutIfNeeded()
    }

    private func startHovering() {
        guard !isReturningToLibrary, !UIAccessibility.isReduceMotionEnabled else { return }
        // Start at the exact lift endpoint rather than jumping to a new pose.
        let hover = CAKeyframeAnimation(keyPath: "transform.translation.y")
        hover.values = [0, -3, 0, 3, 0]
        hover.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        hover.duration = 3.2
        hover.repeatCount = .infinity
        hover.calculationMode = .cubic
        cover.layer.add(hover, forKey: "Sumi.Hover")
    }

    func stopHovering() {
        // Keep the visible pose as the source of the opening transition.
        // Removing an additive animation without this snaps to its model pose.
        let visible = cover.layer.presentation()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let visible {
            cover.layer.position = visible.position
            cover.layer.transform = visible.transform
        }
        cover.layer.removeAnimation(forKey: "Sumi.Hover")
        CATransaction.commit()
    }

    private func loadingRegion() -> CGRect {
        let usable = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 24, dy: 24)
        var exclusions: [CGRect] = []
        if #available(iOS 27.1, *) {
            exclusions = (view.reservedRegions(kind: .division) + view.reservedRegions(kind: .occlusion))
                .filter(\.isActive).map(\.frame)
        }
        return ReaderControlLayout.availableRegions(in: usable, avoiding: exclusions)
            .filter { $0.width >= 100 && $0.height >= 100 }
            .max { lhs, rhs in
                let difference = lhs.width * lhs.height - rhs.width * rhs.height
                if abs(difference) > 1 { return difference < 0 }
                return lhs.maxX + lhs.maxY < rhs.maxX + rhs.maxY
            } ?? usable
    }

    private func openingCoverFrame() -> CGRect {
        let usable = loadingRegion()
        let height = max(1, min(usable.height * 0.70, usable.width * 0.72 / canvasAspect, 480))
        let size = CGSize(width: height * canvasAspect, height: height)
        return CGRect(x: usable.midX - size.width / 2, y: usable.midY - size.height / 2 - 12,
                      width: size.width, height: size.height)
    }

    func prepareOpening() async {
        while isLifting, !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(20)) }
            catch { return }
        }
        guard !Task.isCancelled, !isReturningToLibrary else { return }
        isPreparingOpening = true
        stopHovering()
        activity.stopAnimating()
        await withCheckedContinuation { continuation in
            UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.1 : 0.18) {
                self.loadingPill.alpha = 0
            } completion: { _ in continuation.resume() }
        }
    }

    func coverSnapshot() -> UIImage? {
        if let snapshot { return snapshot }
        guard cover.bounds.width > 1, cover.bounds.height > 1 else { return nil }
        return UIGraphicsImageRenderer(bounds: cover.bounds).image { _ in
            cover.drawHierarchy(in: cover.bounds, afterScreenUpdates: false)
        }
    }

    func showLoading() {
        loadViewIfNeeded()
        hasError = false
        loadingPill.layer.removeAllAnimations()
        view.isUserInteractionEnabled = true
        closeButton.isHidden = true
        message.isHidden = true
        retryButton.isHidden = true
        cover.isHidden = false
        loadingPill.alpha = 1
        loadingPill.isHidden = false
        activity.startAnimating()
    }

    func showError(_ text: String) {
        hasError = true
        view.isUserInteractionEnabled = true
        closeButton.isHidden = false
        activity.stopAnimating()
        loadingPill.isHidden = true
        message.text = text
        message.isHidden = false
        retryButton.isHidden = false
    }

    /// Lower the same visible edition back into its live grid position.
    /// The provider is evaluated after layout so a resized grid can supply its
    /// current tile frame rather than the frame captured at pickup.
    func returnToSource(frame: @escaping () -> CGRect?, completion: @escaping () -> Void) {
        loadViewIfNeeded()
        guard !isReturningToLibrary else { return }
        isReturningToLibrary = true
        isPreparingOpening = true
        isLifting = false
        view.isUserInteractionEnabled = false

        // A cancelled lift can still be between its grid and hover positions.
        // Freeze that presentation pose before replacing its animation.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let visible = cover.layer.presentation() {
            cover.layer.position = visible.position
            cover.layer.bounds = visible.bounds
            cover.layer.transform = visible.transform
        }
        if let visible = dimming.layer.presentation() { dimming.layer.opacity = visible.opacity }
        if let visible = loadingPill.layer.presentation() { loadingPill.layer.opacity = visible.opacity }
        cover.layer.removeAllAnimations()
        dimming.layer.removeAllAnimations()
        loadingPill.layer.removeAllAnimations()
        CATransaction.commit()
        activity.stopAnimating()
        view.layoutIfNeeded()
        let target = frame().flatMap { $0.isEmpty || $0.isInfinite || $0.isNull ? nil : $0 }
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.44,
                       delay: 0, usingSpringWithDamping: 0.90, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState]) {
            if let target {
                self.cover.layer.transform = CATransform3DIdentity
                self.cover.frame = target
                self.cover.layoutIfNeeded()
            } else {
                self.cover.alpha = 0
            }
            self.dimming.alpha = 0
            self.loadingPill.alpha = 0
            self.status.alpha = 0
        } completion: { _ in completion() }
    }

    func cancelOpeningIfOutsideCover(at point: CGPoint) {
        guard !isReturningToLibrary else { return }
        let visibleFrame = cover.layer.presentation()?.frame ?? cover.frame
        guard hasError || !visibleFrame.contains(point) else { return }
        closeBook?()
    }

    @objc private func cancelOpeningFromTap(_ gesture: UITapGestureRecognizer) {
        cancelOpeningIfOutsideCover(at: gesture.location(in: view))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Retry remains an independent error action. All other space outside
        // the visible cover, including the error message, cancels opening.
        var target = touch.view
        while let candidate = target, candidate !== view {
            if candidate is UIControl { return false }
            target = candidate.superview
        }
        return !isReturningToLibrary
    }

    override func accessibilityPerformEscape() -> Bool {
        guard !isReturningToLibrary, let closeBook else { return false }
        closeBook()
        return true
    }
}
#endif
