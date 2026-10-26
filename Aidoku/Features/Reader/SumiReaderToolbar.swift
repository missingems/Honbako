#if SUMI
import UIKit

/// Three independent controls keep navigation separate from page exploration.
/// This view positions them as a group without adding a fourth material surface.
final class SumiReaderToolbar: UIView {
    var close: (() -> Void)?
    var chapters: (() -> Void)?
    var expandsHorizontalStrip = false {
        didSet {
            guard expandsHorizontalStrip != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }
    var axis: NSLayoutConstraint.Axis = .horizontal {
        didSet {
            guard axis != oldValue else { return }
            scrubber?.axis = axis
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }
    var sidebarEdge: UIRectEdge = .right {
        didSet { scrubber?.sidebarEdge = sidebarEdge }
    }
    var chaptersAnchorView: UIView { chaptersButton }
    private(set) var isVisible = false

    private let closeGlass = UIVisualEffectView()
    private let scrubberGlass = UIVisualEffectView()
    private let chaptersGlass = UIVisualEffectView()
    private let closeButton = UIButton(type: .system)
    private let chaptersButton = UIButton(type: .system)
    private weak var scrubber: SumiPageScrubber?
    private var visibilityAnimator: UIViewPropertyAnimator?
    private var visibilityIdentity = UUID()
    private var surfaces: [UIVisualEffectView] { [closeGlass, scrubberGlass, chaptersGlass] }

    static func makeGlassEffect() -> UIGlassEffect {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        effect.tintColor = UIColor(white: 0.08, alpha: 0.72)
        return effect
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "Sumi.Reader.Toolbar"
        isAccessibilityElement = false
        shouldGroupAccessibilityChildren = true
        backgroundColor = .clear
        for (surface, identifier) in zip(surfaces, ["Close", "Scrubber", "Chapters"]) {
            surface.accessibilityIdentifier = "Sumi.Reader.\(identifier).Glass"
            surface.overrideUserInterfaceStyle = .dark
            surface.clipsToBounds = true
            surface.layer.cornerCurve = .continuous
            surface.contentView.backgroundColor = UIColor(white: 0.08, alpha: 0.28)
            addSubview(surface)
        }
        configure(closeButton, image: "xmark", label: "Close book", identifier: "SumiReader.Close")
        configure(chaptersButton, image: "list.bullet", label: "Chapters and language", identifier: "Sumi.Reader.ChaptersButton")
        closeButton.addAction(UIAction { [weak self] _ in self?.close?() }, for: .touchUpInside)
        chaptersButton.addAction(UIAction { [weak self] _ in self?.chapters?() }, for: .touchUpInside)
        closeGlass.contentView.addSubview(closeButton)
        chaptersGlass.contentView.addSubview(chaptersButton)
        alpha = 0
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure(_ button: UIButton, image: String, label: String, identifier: String) {
        button.setImage(UIImage(systemName: image), for: .normal)
        button.tintColor = .white
        button.accessibilityLabel = label
        button.accessibilityIdentifier = identifier
        button.isPointerInteractionEnabled = true
    }

    override var intrinsicContentSize: CGSize { preferredSize(availableLength: .greatestFiniteMagnitude) }

    func preferredSize(availableLength: CGFloat) -> CGSize {
        let desired: CGFloat = axis == .vertical ? 380 : (expandsHorizontalStrip ? 620 : 420)
        let length = min(desired, max(1, availableLength))
        return axis == .vertical ? CGSize(width: SumiScrubberMetrics.toolbarThickness, height: length)
            : CGSize(width: length, height: SumiScrubberMetrics.toolbarThickness)
    }

    func mount(_ scrubber: SumiPageScrubber) {
        self.scrubber = scrubber
        scrubber.usesSharedToolbarGlass = true
        scrubber.sidebarEdge = sidebarEdge
        scrubber.axis = axis
        scrubber.isHidden = false
        scrubber.alpha = 1
        scrubberGlass.contentView.addSubview(scrubber)
        accessibilityElements = [closeButton, scrubber, chaptersButton]
        updateOverlayVisibility()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let vertical = axis == .vertical
        let length = vertical ? bounds.height : bounds.width
        let thickness = vertical ? bounds.width : bounds.height
        let button: CGFloat = min(48, thickness)
        // Small windows compress the filmstrip, never its navigation targets.
        let gap: CGFloat = length >= 200 ? 6 : 4
        let stripLength = max(0, length - button * 2 - gap * 2)
        func frame(start: CGFloat, length: CGFloat, cross: CGFloat) -> CGRect {
            vertical
                ? CGRect(x: (thickness - cross) / 2, y: start, width: cross, height: length)
                : CGRect(x: start, y: (thickness - cross) / 2, width: length, height: cross)
        }
        closeGlass.frame = frame(start: 0, length: button, cross: button)
        scrubberGlass.frame = frame(start: button + gap, length: stripLength, cross: thickness)
        chaptersGlass.frame = frame(start: length - button, length: button, cross: button)
        closeGlass.layer.cornerRadius = min(closeGlass.bounds.width, closeGlass.bounds.height) / 2
        scrubberGlass.layer.cornerRadius = SumiScrubberMetrics.cornerRadius
        chaptersGlass.layer.cornerRadius = min(chaptersGlass.bounds.width, chaptersGlass.bounds.height) / 2
        closeButton.frame = closeGlass.bounds
        chaptersButton.frame = chaptersGlass.bounds
        scrubber?.frame = scrubberGlass.bounds
        scrubber?.layoutIfNeeded()
    }

    // The empty space between components belongs to the book beneath them.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        surfaces.contains { $0.frame.contains(point) }
    }

    override var alpha: CGFloat { didSet { updateOverlayVisibility() } }
    override var isHidden: Bool { didSet { updateOverlayVisibility() } }

    private func updateOverlayVisibility() {
        scrubber?.setToolbarVisibility(alpha: alpha, isHidden: isHidden)
    }

    func setVisible(_ visible: Bool, animated: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        visibilityIdentity = UUID()
        let identity = visibilityIdentity
        visibilityAnimator?.stopAnimation(true)
        visibilityAnimator = nil
        if visible { isHidden = false }
        let changes = {
            for surface in self.surfaces { surface.effect = visible ? Self.makeGlassEffect() : nil }
            self.alpha = visible ? 1 : 0
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
