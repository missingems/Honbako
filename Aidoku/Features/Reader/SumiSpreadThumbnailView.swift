#if SUMI
import UIKit

/// Reused by the filmstrip and the larger floating preview.
final class SumiSpreadThumbnailView: UIView {
    private let contentSurface = UIView()
    private let images = [UIImageView(), UIImageView()]
    private let placeholders = [UIView(), UIView()]
    private let indicators = [UIActivityIndicatorView(style: .medium), UIActivityIndicatorView(style: .medium)]
    private var tasks: [Task<Void, Never>] = []
    private var pendingLoads = 0
    private var loadedPages: Set<Int> = []
    private var identity = ""
    private var requestedPages: [Int] = []
    private var request = UUID()
    private(set) var displayedPages: [Int] = []
    private var onReady: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        layer.cornerCurve = .continuous
        clipsToBounds = true
        contentSurface.isUserInteractionEnabled = false
        addSubview(contentSurface)
        for (index, image) in images.enumerated() {
            let placeholder = placeholders[index]
            placeholder.backgroundColor = UIColor(white: 0.75, alpha: 0.32)
            placeholder.layer.cornerCurve = .continuous
            placeholder.clipsToBounds = true
            placeholder.isAccessibilityElement = false
            placeholder.isUserInteractionEnabled = false
            contentSurface.addSubview(placeholder)
            let indicator = indicators[index]
            indicator.color = .secondaryLabel
            indicator.hidesWhenStopped = true
            placeholder.addSubview(indicator)
            image.contentMode = .scaleAspectFill
            image.layer.cornerCurve = .continuous
            image.clipsToBounds = true
            image.isAccessibilityElement = false
            contentSurface.addSubview(image)
        }
        isAccessibilityElement = true
        accessibilityTraits = .image
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { tasks.forEach { $0.cancel() } }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentSurface.frame = bounds
        let count = max(1, requestedPages.count)
        let radius = min(SumiPreviewGeometry.radius(in: bounds), bounds.width / CGFloat(count) / 2)
        layer.cornerRadius = radius
        for (index, image) in images.enumerated() {
            image.isHidden = index >= count
            let slot = CGRect(x: CGFloat(index) * bounds.width / CGFloat(count), y: 0,
                              width: bounds.width / CGFloat(count), height: bounds.height)
            image.frame = slot
            let corners = SumiPreviewGeometry.outerCorners(leaf: index, count: count)
            image.layer.maskedCorners = corners
            image.layer.cornerRadius = min(radius, min(image.bounds.width, image.bounds.height) / 2)
            let placeholder = placeholders[index]
            placeholder.frame = slot
            placeholder.layer.maskedCorners = corners
            placeholder.layer.cornerRadius = radius
            if index >= count { placeholder.isHidden = true }
            let indicator = indicators[index]
            indicator.center = CGPoint(x: placeholder.bounds.midX, y: placeholder.bounds.midY)
            let scale = min(1, max(0.4, min(placeholder.bounds.width, placeholder.bounds.height) / 34))
            indicator.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }

    func installDecoration(_ view: UIView) {
        contentSurface.insertSubview(view, at: 0)
    }

    func bounce() {
        stopBounce()
        layoutIfNeeded()
        guard !isHidden, window != nil, !UIAccessibility.isReduceMotionEnabled else { return }
        // The artwork and surrounding glass are a single physical preview.
        contentSurface.layer.add(SumiScrubHoverGlassView.bounceAnimation(), forKey: "Sumi.Preview.Bounce")
    }

    func stopBounce() {
        contentSurface.layer.removeAnimation(forKey: "Sumi.Preview.Bounce")
    }

    func configure(identity: String = "", pages: [Int], reversed: Bool,
                   preservingCurrent _: Bool = false, provider: ((Int) async -> UIImage?)?, ready: ((Bool) -> Void)? = nil) {
        let physical = Array((reversed ? Array(pages.reversed()) : pages).prefix(2))
        guard !physical.isEmpty else {
            cancelImage(clear: true); accessibilityValue = String(localized: "Preview unavailable"); ready?(false); return
        }
        onReady = ready
        let samePages = self.identity == identity && requestedPages == physical
        if samePages {
            if displayedPages == physical {
                accessibilityValue = String(localized: "Preview ready"); ready?(true); return
            }
            if pendingLoads > 0 { return }
        }
        tasks.forEach { $0.cancel() }; tasks = []; request = UUID()
        let id = request
        self.identity = identity
        requestedPages = physical
        displayedPages = []
        if !samePages { loadedPages = [] }
        pendingLoads = physical.filter { !loadedPages.contains($0) }.count
        accessibilityLabel = pages.count == 2 ? String(localized: "Pages \(pages[0]) and \(pages[1])") : String(localized: "Page \(pages.first ?? 1)")
        accessibilityValue = String(localized: "Loading preview")
        for (index, image) in images.enumerated() {
            image.layer.removeAllAnimations()
            let loaded = physical[safe: index].map { loadedPages.contains($0) } ?? false
            if !loaded { image.image = nil }
            image.alpha = loaded ? 1 : 0
            let placeholder = placeholders[index]
            placeholder.isHidden = index >= physical.count || loaded
            placeholder.accessibilityIdentifier = physical[safe: index].map { "Sumi.Reader.PreviewPlaceholder.\($0)" }
            if index < physical.count, !loaded { indicators[index].startAnimating() }
            else { indicators[index].stopAnimating() }
        }
        setNeedsLayout()
        // Each leaf owns its placeholder. A late half of a spread may fade in
        // independently without ever pairing new artwork with the previous spread.
        for (index, page) in physical.enumerated() where !loadedPages.contains(page) {
            let task = Task { [weak self] in
                let image = await provider?(page)
                guard !Task.isCancelled, let self, request == id else { return }
                pendingLoads -= 1
                if let image {
                    loadedPages.insert(page)
                    publish(image, at: index, request: id)
                } else {
                    indicators[index].stopAnimating()
                }
                guard pendingLoads == 0 else { return }
                tasks = []
                let complete = loadedPages.count == physical.count
                displayedPages = complete ? physical : []
                accessibilityValue = complete ? String(localized: "Preview ready") : String(localized: "Preview unavailable")
                onReady?(complete)
            }
            tasks.append(task)
        }
    }

    private func publish(_ image: UIImage, at index: Int, request id: UUID) {
        let imageView = images[index]
        let placeholder = placeholders[index]
        imageView.image = image
        // Crop into the same fixed surface as the placeholder before fading,
        // so a tall page never collapses into a thin strip of artwork.
        setNeedsLayout()
        layoutIfNeeded()
        indicators[index].stopAnimating()
        let duration: TimeInterval = window != nil && !UIAccessibility.isReduceMotionEnabled ? 0.2 : 0
        guard duration > 0 else {
            imageView.alpha = 1
            placeholder.isHidden = true
            return
        }
        UIView.animate(withDuration: duration, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]) {
            imageView.alpha = 1
        } completion: { [weak self] _ in
            guard self?.request == id else { return }
            placeholder.isHidden = true
        }
    }

    func cancelImage(clear: Bool = false) {
        tasks.forEach { $0.cancel() }; tasks = []; pendingLoads = 0
        request = UUID(); onReady = nil
        for (index, image) in images.enumerated() {
            image.layer.removeAllAnimations()
            image.alpha = image.image == nil ? 0 : 1
            indicators[index].stopAnimating()
            if image.image != nil { placeholders[index].isHidden = true }
        }
        if clear {
            identity = ""; requestedPages = []; displayedPages = []; loadedPages = []
            images.forEach { $0.image = nil; $0.alpha = 0 }
            placeholders.forEach { $0.isHidden = true }
            setNeedsLayout()
        }
    }
}
#endif
