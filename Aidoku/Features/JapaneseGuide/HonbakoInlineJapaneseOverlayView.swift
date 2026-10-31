#if SUMI
import UIKit

/// Annotation-only content. It is a child of the actual image view, so zooming
/// and page cropping move the genuine word anchors with the manga artwork.
@MainActor
final class HonbakoInlineJapaneseOverlayView: UIView {
    private let recognitionStore: HonbakoInlineJapaneseRecognitionStore
    private var image: UIImage?
    private var regions: [HonbakoJapaneseRegion]?
    private var recognitionTask: Task<Void, Never>?
    private var generation = 0
    private var enabled = false
    private var pageVisible = false
    private var applicationActive = true
    private var sceneActive = true
    private var snapshotDepth = 0
    private var onSelect: HonbakoJapaneseSelectionHandler?
    private var buttons: [HonbakoInlineJapaneseWordButton] = []
    private var buttonsByID: [String: HonbakoInlineJapaneseWordButton] = [:]
    private var renderedSize: CGSize = .zero
    private var renderedCategory: UIContentSizeCategory?
    private var needsAnnotationLayout = true
    private var renderedExclusions: [CGRect] = []
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(recognitionStore: HonbakoInlineJapaneseRecognitionStore = .shared) {
        self.recognitionStore = recognitionStore
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isHidden = true
        accessibilityElementsHidden = true
        accessibilityIdentifier = "Honbako.Reader.Japanese.Overlay"
        spinner.isUserInteractionEnabled = false
        spinner.isAccessibilityElement = false
        spinner.color = .secondaryLabel
        addSubview(spinner)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(suspendApplication), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(resumeApplication), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(suspendScene(_:)), name: UIScene.willDeactivateNotification, object: nil)
        center.addObserver(self, selector: #selector(resumeScene(_:)), name: UIScene.didActivateNotification, object: nil)
        center.addObserver(self, selector: #selector(contentSizeChanged), name: UIContentSizeCategory.didChangeNotification, object: nil)
    }

    override convenience init(frame: CGRect) {
        self.init(recognitionStore: .shared)
        self.frame = frame
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        recognitionTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func configure(enabled: Bool, onSelect: HonbakoJapaneseSelectionHandler?) {
        self.onSelect = onSelect
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        refreshEligibility()
    }

    func update(image: UIImage?) {
        guard self.image !== image else { return }
        cancelRecognition()
        self.image = image
        regions = nil
        clearAnnotations()
        needsAnnotationLayout = true
        refreshEligibility()
    }

    /// Image layout can run inside the status-bar animation. Match its final
    /// geometry immediately; the image ancestor already owns zoom/page motion.
    func updateImageFrame(_ frame: CGRect) {
        Self.withoutInheritedAnimations {
            if self.frame != frame { self.frame = frame }
            refreshEligibility()
            if !isHidden, renderedSize != bounds.size
                || renderedCategory != traitCollection.preferredContentSizeCategory
                || renderedExclusions != reservedControlFrames || needsAnnotationLayout {
                setNeedsLayout()
            }
            layoutIfNeeded()
        }
    }

    func setPageVisible(_ visible: Bool) {
        guard pageVisible != visible else {
            if visible { refreshEligibility() }
            return
        }
        pageVisible = visible
        refreshEligibility()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        sceneActive = window?.windowScene?.activationState == .foregroundActive
        applicationActive = UIApplication.shared.applicationState == .active
        refreshEligibility()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Status and toolbar changes can lay out this image inside a UIKit
        // animation. Reading aids are anchored content, so their own geometry
        // must never inherit the chrome's slide or animate from zero-sized views.
        Self.withoutInheritedAnimations {
            refreshEligibility()
            spinner.frame = CGRect(x: max(0, bounds.maxX - 30), y: bounds.minY + 8, width: 22, height: 22)
            guard !isHidden else { return }
            let exclusions = reservedControlFrames
            if renderedSize != bounds.size || renderedCategory != traitCollection.preferredContentSizeCategory
                || renderedExclusions != exclusions || needsAnnotationLayout {
                layoutAnnotations(excluding: exclusions)
            }
        }
    }

    private var canRecognize: Bool {
        guard enabled, pageVisible, image != nil, window != nil, applicationActive, sceneActive,
              bounds.width > 0, bounds.height > 0 else { return false }
        var ancestor = superview
        while let view = ancestor {
            if view.isHidden || view.alpha < 0.01 { return false }
            ancestor = view.superview
        }
        return true
    }

    private func refreshEligibility() {
        guard snapshotDepth == 0 else { return }
        guard canRecognize else {
            cancelRecognition()
            isHidden = true
            accessibilityElementsHidden = true
            spinner.stopAnimating()
            return
        }
        let wasHidden = isHidden
        isHidden = false
        accessibilityElementsHidden = false
        if regions != nil {
            if wasHidden { setNeedsLayout() }
            return
        }
        guard recognitionTask == nil, let image else { return }
        generation &+= 1
        let expected = generation
        let store = recognitionStore
        spinner.startAnimating()
        recognitionTask = Task { [weak self] in
            do {
                let result = try await store.regions(for: image)
                try Task.checkCancellation()
                guard let self, self.generation == expected, self.image === image, self.canRecognize else { return }
                self.recognitionTask = nil
                self.regions = result
                self.spinner.stopAnimating()
                self.needsAnnotationLayout = true
                self.setNeedsLayout()
            } catch {
                guard let self, self.generation == expected else { return }
                self.recognitionTask = nil
                self.spinner.stopAnimating()
                // Empty/non-Japanese/unreadable pages remain ordinary reading pages.
                if !(error is CancellationError) { self.regions = [] }
            }
        }
    }

    private func cancelRecognition() {
        guard recognitionTask != nil else { return }
        generation &+= 1
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func clearAnnotations() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll(keepingCapacity: true)
        buttonsByID.removeAll(keepingCapacity: true)
    }

    private var reservedControlFrames: [CGRect] {
        if #available(iOS 27.1, *) {
            return (reservedRegions(kind: .division) + reservedRegions(kind: .occlusion)).filter(\.isActive).map(\.frame)
        }
        return []
    }

    private func layoutAnnotations(excluding exclusions: [CGRect]) {
        renderedExclusions = exclusions
        renderedSize = bounds.size
        renderedCategory = traitCollection.preferredContentSizeCategory
        needsAnnotationLayout = false
        guard let regions, !bounds.isEmpty else { clearAnnotations(); return }
        // Reuse the same views when a toolbar/status-bar layout changes the
        // available image geometry. Only another image discards its word views.
        buttons.removeAll(keepingCapacity: true)
        let boxes = Dictionary(uniqueKeysWithValues: regions.compactMap { region -> (Int, CGRect)? in
            guard let rect = HonbakoJapaneseGeometry.rect(for: region.boundingBox, in: bounds) else { return nil }
            return (region.id, rect)
        })
        var occupied = Array(boxes.values)
        // The reader image itself can cross the fold; the little controls cannot.
        occupied.append(contentsOf: exclusions)
        let font = Self.annotationFont(compatibleWith: traitCollection)
        let gap = UIFontMetrics(forTextStyle: .caption2).scaledValue(for: 1.5, compatibleWith: traitCollection)
        for region in regions {
            guard let box = boxes[region.id] else { continue }
            let phrase = makeButton(region: region, word: nil, title: nil)
            phrase.frame = box
            let wordFrames = HonbakoJapaneseOverlayLayout.distinctWordFrames(Dictionary(uniqueKeysWithValues:
                region.words.compactMap { anchored -> (Int, CGRect)? in
                    guard let normalized = anchored.boundingBox,
                          let rect = HonbakoJapaneseGeometry.rect(for: normalized, in: bounds) else { return nil }
                    return (anchored.id, rect)
                }
            ))
            // Lexical words retain translation targets. Visible readings use
            // exact character/mora anchors, with no newly invented geometry.
            let characters = region.characters.isEmpty ? region.words.compactMap { item -> HonbakoJapaneseCharacterRegion? in
                guard let romaji = item.word.romaji else { return nil }
                return .init(character: .init(wordID: item.word.id, text: item.word.text, romaji: romaji,
                    range: item.word.range), boundingBox: item.boundingBox, ink: .black)
            } : region.characters
            let characterFrames = HonbakoJapaneseOverlayLayout.distinctWordFrames(Dictionary(uniqueKeysWithValues:
                characters.compactMap { item -> (Int, CGRect)? in
                    guard let normalized = item.boundingBox,
                          let frame = HonbakoJapaneseGeometry.rect(for: normalized, in: bounds) else { return nil }
                    return (item.id, frame)
                }))
            var chosen: [Int: CGRect] = [:]
            for side in HonbakoJapaneseOverlaySide.preferred(for: region.direction) {
                var proposed: [Int: CGRect] = [:]
                var localOccupied = occupied
                for item in characters {
                    guard let characterBox = characterFrames[item.id] else { continue }
                    let size = HonbakoJapaneseAnnotationStyle.labelSize(
                        for: item.character.romaji, font: font, direction: region.direction, wordBox: characterBox)
                    guard let frame = HonbakoJapaneseOverlayLayout.wordChipFrame(
                        for: characterBox, in: bounds, size: size, direction: region.direction,
                        containingTextBox: box, side: side, spacing: gap, avoiding: localOccupied
                    ) else { continue }
                    proposed[item.id] = frame
                    localOccupied.append(frame)
                }
                if proposed.count > chosen.count { chosen = proposed }
            }
            occupied.append(contentsOf: chosen.values)
            for anchored in region.words {
                guard let frame = wordFrames[anchored.id] else { continue }
                let target = makeButton(region: region, word: anchored.word, title: nil)
                target.frame = frame
                if characters.contains(where: { $0.character.wordID == anchored.id && chosen[$0.id] != nil }) {
                    target.isAccessibilityElement = false
                }
            }
            for item in characters {
                guard let frame = chosen[item.id],
                      let word = region.words.first(where: { $0.id == item.character.wordID })?.word else { continue }
                let button = makeButton(region: region, word: word, title: item.character.romaji,
                    annotationID: item.id, ink: item.ink, sourceText: item.character.text)
                button.frame = frame
            }
        }
        let currentIDs = Set(buttons.compactMap(\.accessibilityIdentifier))
        for identifier in buttonsByID.keys.filter({ !currentIDs.contains($0) }) {
            buttonsByID.removeValue(forKey: identifier)?.removeFromSuperview()
        }
        for button in buttons { button.layoutIfNeeded() }
        bringSubviewToFront(spinner)
    }

    private func makeButton(
        region: HonbakoJapaneseRegion, word: HonbakoJapaneseWord?, title: String?,
        annotationID: Int? = nil, ink: HonbakoJapaneseInk = .black, sourceText: String? = nil
    ) -> HonbakoInlineJapaneseWordButton {
        let identifier: String
        if let word {
            let kind = title == nil ? "WordTarget" : "Word"
            identifier = "Honbako.Reader.Japanese.\(kind).\(region.id).\(annotationID ?? word.id)"
        } else { identifier = "Honbako.Reader.Japanese.Phrase.\(region.id)" }
        let button = buttonsByID[identifier] ?? HonbakoInlineJapaneseWordButton(frame: .zero)
        buttonsByID[identifier] = button
        button.accessibilityIdentifier = identifier
        button.isAccessibilityElement = true
        button.isExclusiveTouch = false
        button.accessibilityHint = String(localized: "Hear the pronunciation or reveal a translation")
        if let word {
            button.accessibilityLabel = [sourceText ?? word.text, title ?? word.romaji].compactMap { $0 }.joined(separator: ", ")
            button.accessibilityValue = title ?? word.romaji
        } else {
            button.accessibilityLabel = region.text
        }
        button.titleLabel.text = title
        if ink == .black { button.titleLabel.textColor = .black }
        else if ink == .white { button.titleLabel.textColor = .white }
        else {
            button.titleLabel.textColor = UIColor(red: CGFloat(ink.red) / 255, green: CGFloat(ink.green) / 255,
                                                  blue: CGFloat(ink.blue) / 255, alpha: 1)
        }
        button.activate = { [weak self, weak button] in
            guard let self, let button, let select = self.onSelect, self.canRecognize, !self.isHidden else { return false }
            select(region, word?.id, button.convert(button.bounds, to: nil))
            return true
        }
        buttons.append(button)
        if button.superview !== self { addSubview(button) }
        return button
    }

    private var visibleAnnotationBounds: CGRect {
        var visible = bounds
        var ancestor = superview
        while let view = ancestor {
            if view.clipsToBounds || view is UIWindow {
                visible = visible.intersection(convert(view.bounds, from: view))
            }
            ancestor = view.superview
        }
        return visible
    }

    override var accessibilityElements: [Any]? {
        get {
            guard !isHidden, !accessibilityElementsHidden else { return [] }
            let visible = visibleAnnotationBounds
            return buttons.filter { $0.isAccessibilityElement && !$0.isHidden && visible.intersects($0.frame) }
        }
        set {
            // Enumerate the live viewport rather than retaining the last scroll
            // position. Image ancestors perform visual clipping without hiding
            // individual words that may scroll into view on the next frame.
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
        for button in buttons.reversed() where !button.isHidden {
            let local = button.convert(point, from: self)
            if button.point(inside: local, with: event) { return button.hitTest(local, with: event) }
        }
        return nil
    }

    fileprivate static func annotationFont(compatibleWith traits: UITraitCollection) -> UIFont {
        UIFontMetrics(forTextStyle: .caption2).scaledFont(
            for: .systemFont(ofSize: 8), compatibleWith: traits)
    }

    fileprivate static func withoutInheritedAnimations(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation(changes)
        CATransaction.commit()
    }

    static func isInteractiveTarget(_ view: UIView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is HonbakoInlineJapaneseWordButton { return true }
            current = candidate.superview
        }
        return false
    }

    /// Curl and library-return snapshots contain artwork only. Scope is the
    /// supplied reader subtree, and nested captures restore the exact prior state.
    static func withSnapshotsSuppressed<T>(in root: UIView, _ operation: () -> T) -> T {
        var hosts: [(HonbakoInlineJapaneseOverlayView, Bool)] = []
        func collect(_ view: UIView) {
            if let host = view as? HonbakoInlineJapaneseOverlayView { hosts.append((host, host.isHidden)) }
            view.subviews.forEach(collect)
        }
        collect(root)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (host, _) in hosts {
            host.snapshotDepth += 1
            host.isHidden = true
        }
        CATransaction.commit()
        defer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (host, wasHidden) in hosts {
                host.snapshotDepth -= 1
                host.isHidden = wasHidden
            }
            CATransaction.commit()
        }
        return operation()
    }

    @objc private func suspendApplication() { applicationActive = false; refreshEligibility() }
    @objc private func resumeApplication() { applicationActive = true; refreshEligibility() }
    @objc private func contentSizeChanged() { needsAnnotationLayout = true; setNeedsLayout() }
    @objc private func suspendScene(_ notification: Notification) {
        guard let scene = notification.object as? UIScene, scene === window?.windowScene else { return }
        sceneActive = false
        refreshEligibility()
    }
    @objc private func resumeScene(_ notification: Notification) {
        guard let scene = notification.object as? UIScene, scene === window?.windowScene else { return }
        sceneActive = true
        refreshEligibility()
    }
}

/// A scroll view can cancel touches in an ordinary view when a drag begins.
/// UIControl targets opt out of that default cancellation and block Webtoon pans.
private final class HonbakoInlineJapaneseWordButton: UIView {
    let titleLabel = UILabel()
    var activate: (() -> Bool)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        titleLabel.font = HonbakoInlineJapaneseOverlayView.annotationFont(compatibleWith: traitCollection)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .black
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byCharWrapping
        titleLabel.isAccessibilityElement = false
        titleLabel.isUserInteractionEnabled = false
        addSubview(titleLabel)
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        HonbakoInlineJapaneseOverlayView.withoutInheritedAnimations {
            let font = HonbakoInlineJapaneseOverlayView.annotationFont(compatibleWith: traitCollection)
            if titleLabel.font != font { titleLabel.font = font }
            titleLabel.frame = bounds
        }
    }

    override func accessibilityActivate() -> Bool {
        activate?() ?? false
    }

    @objc private func didTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, bounds.contains(recognizer.location(in: self)) else { return }
        _ = activate?()
    }
}
#endif
