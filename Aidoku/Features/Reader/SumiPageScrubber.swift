#if SUMI
import UIKit

final class SumiPageScrubber: UIControl, UICollectionViewDataSource, UICollectionViewDelegate {
    var onCommit: ((Int) -> Void)?
    /// Animate through complete canonical pages instead of exposing a new page
    /// behind an opaque handoff. The reader owns each curl and cancellation.
    var navigateToPage: ((Int) async -> Bool)?
    /// Floating artwork belongs to the reader overlay, not a clipped toolbar.
    weak var previewContainer: UIView? {
        didSet { updateFloatingHost(); setNeedsLayout() }
    }
    var accessibilityOverlayView: UIView? { previewContainer == nil ? nil : floatingOverlay }
    /// A unified reader toolbar supplies the material for the whole rail.
    var usesSharedToolbarGlass = false {
        didSet {
            guard usesSharedToolbarGlass != oldValue else { return }
            if usesSharedToolbarGlass {
                glass.effect = nil
                glass.isHidden = true
                rail.insertSubview(collection, belowSubview: lens)
            } else {
                glass.effect = SumiReaderToolbar.makeGlassEffect()
                glass.isHidden = false
                glass.contentView.addSubview(collection)
            }
            setNeedsLayout()
        }
    }
    var axis: NSLayoutConstraint.Axis = .horizontal {
        didSet {
            guard axis != oldValue else { return }
            panning = false
            collection.setContentOffset(collection.contentOffset, animated: false)
            cancelPreview(); collection.reloadData(); needsPosition = true
            invalidateIntrinsicContentSize(); setNeedsLayout()
        }
    }
    /// The native toolbar's physical edge, used only for the inward hover.
    var sidebarEdge: UIRectEdge = .right {
        didSet { if sidebarEdge != oldValue { setNeedsLayout() } }
    }
    var preparePage: ((Int) async -> Bool)?
    var imageProvider: ((Int) async -> UIImage?)?
    var hoverImageProvider: ((Int) async -> UIImage?)?
    var landingSurface: (() -> UIView?)?
    var isLandingReady: ((Int) -> Bool)?
    /// Logical ordering of cells along the native scroll axis. Sumi uses false:
    /// a leftward horizontal drag (upward in a side bar) reveals later pages.
    var isReversed = false {
        didSet {
            guard oldValue != isReversed else { return }
            cancelPreview(); collection.reloadData(); needsPosition = true; setNeedsLayout()
        }
    }
    /// Source page order inside one preview is separate from strip progression.
    /// A source still prints its own first leaf on the correct physical side,
    /// independently of the direction in which the filmstrip is dragged.
    var reversesThumbnailPages = false {
        didSet {
            guard oldValue != reversesThumbnailPages else { return }
            cancelPreview(); collection.reloadData(); setNeedsLayout()
        }
    }
    private let glass = UIVisualEffectView(effect: SumiReaderToolbar.makeGlassEffect())
    private let rail = UIView()
    private let floatingOverlay = UIView()
    private let glassTint = UIView()
    private let lens = SumiScrubberLensView()
    private let flow = SumiFilmstripLayout()
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: flow)
    private let edgeFade = CAGradientLayer()
    private let positionGlass = UIVisualEffectView(effect: {
        let effect = UIGlassEffect(style: .regular)
        effect.tintColor = UIColor(white: 0.08, alpha: 0.48)
        return effect
    }())
    private let pageLabel = UILabel()
    private let preview = SumiSpreadThumbnailView()
    private let feedback = UISelectionFeedbackGenerator()
    private var model = SumiScrubberPages(total: 0)
    private var deferredModel: SumiScrubberPages?
    private var chapterKey = ""
    private var thumbnailRevision = 0
    private var thumbnailIdentity: String { "\(chapterKey)|\(thumbnailRevision)" }
    private var current = 1
    private var reportedCurrent = 1
    private var navigating = false
    private var selectedGroup = 0
    private var scrubbing = false
    private var panning = false
    private var settling = false
    private var lowering = false
    private var landing = false
    private var needsPosition = true
    private var imagesSuspended = false
    private var token = UUID()
    private var settleTask: Task<Void, Never>?
    private var landingTask: Task<Void, Never>?
    private var landingBackdrop: UIView?
    private var isRecoveringSnapshot = false
    private var hoverCenter = CGPoint.zero
    private var toolbarOverlayAlpha: CGFloat = 1
    private var toolbarOverlayHidden = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "Sumi.Reader.Scrubber"
        accessibilityLabel = "Page previews"
        isAccessibilityElement = false; shouldGroupAccessibilityChildren = true
        glass.overrideUserInterfaceStyle = .dark
        glass.layer.cornerRadius = SumiScrubberMetrics.cornerRadius; glass.clipsToBounds = true
        rail.backgroundColor = .clear
        rail.clipsToBounds = false
        addSubview(rail)
        rail.addSubview(glass)
        glassTint.backgroundColor = UIColor(white: 0.02, alpha: 0.18)
        glassTint.isUserInteractionEnabled = false
        glass.contentView.addSubview(glassTint)
        collection.backgroundColor = .clear
        edgeFade.colors = [UIColor.clear.cgColor, UIColor.white.cgColor,
                           UIColor.white.cgColor, UIColor.clear.cgColor]
        edgeFade.startPoint = CGPoint(x: 0, y: 0.5)
        edgeFade.endPoint = CGPoint(x: 1, y: 0.5)
        collection.layer.mask = edgeFade
        collection.contentInsetAdjustmentBehavior = .never
        collection.semanticContentAttribute = .forceLeftToRight
        collection.showsHorizontalScrollIndicator = false
        collection.showsVerticalScrollIndicator = false
        collection.decelerationRate = .normal
        collection.dataSource = self; collection.delegate = self
        collection.register(SumiPageThumbnailCell.self, forCellWithReuseIdentifier: SumiPageThumbnailCell.reuseID)
        collection.accessibilityIdentifier = "Sumi.Reader.ThumbnailStrip"
        collection.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        glass.contentView.addSubview(collection)
        lens.accessibilityIdentifier = "Sumi.Reader.SelectedSpread"
        rail.addSubview(lens)
        positionGlass.overrideUserInterfaceStyle = .dark
        // Keep the count readable while the glass effect is still blurring in.
        positionGlass.contentView.backgroundColor = UIColor(white: 0.08, alpha: 0.68)
        positionGlass.layer.cornerRadius = 15; positionGlass.clipsToBounds = true
        positionGlass.isUserInteractionEnabled = false
        positionGlass.accessibilityIdentifier = "Sumi.Reader.PagePosition"
        pageLabel.textColor = .white
        pageLabel.font = .preferredFont(forTextStyle: .caption1)
        pageLabel.adjustsFontForContentSizeCategory = true; pageLabel.textAlignment = .center
        pageLabel.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Previous spread") { [weak self] _ in self?.accessibilityMove(-1) ?? false },
            UIAccessibilityCustomAction(name: "Next spread") { [weak self] _ in self?.accessibilityMove(1) ?? false }
        ]
        positionGlass.contentView.addSubview(pageLabel); addSubview(positionGlass)
        preview.accessibilityIdentifier = "Sumi.Reader.ScrubPreview"
        preview.isHidden = true
        preview.layer.shadowColor = UIColor.black.cgColor; preview.layer.shadowOpacity = 0.38
        preview.layer.shadowRadius = 16; preview.layer.shadowOffset = CGSize(width: 0, height: 8)
        preview.clipsToBounds = false; addSubview(preview)
        floatingOverlay.backgroundColor = .clear
        floatingOverlay.isUserInteractionEnabled = false
        floatingOverlay.shouldGroupAccessibilityChildren = true
        floatingOverlay.accessibilityIdentifier = "Sumi.Reader.ScrubberOverlay"
        floatingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize {
        axis == .vertical ? CGSize(width: SumiScrubberMetrics.railThickness, height: 260)
            : CGSize(width: 300, height: SumiScrubberMetrics.railThickness)
    }
    override var isHidden: Bool {
        didSet { updateFloatingVisibility() }
    }
    override var alpha: CGFloat {
        didSet { updateFloatingVisibility() }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
        let touchBounds = bounds.insetBy(dx: axis == .vertical ? -4 : 0,
                                        dy: axis == .horizontal ? -4 : 0)
        guard touchBounds.contains(point) else { return nil }
        if let hit = super.hitTest(point, with: event), hit !== self { return hit }
        // The printed rail is thin; its native pan target still spans 48 pt.
        return collection
    }
    deinit { settleTask?.cancel(); landingTask?.cancel() }

    func setToolbarVisibility(alpha: CGFloat, isHidden: Bool) {
        toolbarOverlayAlpha = alpha
        toolbarOverlayHidden = isHidden
        updateFloatingVisibility()
    }

    private func updateFloatingVisibility() {
        floatingOverlay.isHidden = isHidden || toolbarOverlayHidden || window == nil
        floatingOverlay.alpha = alpha * toolbarOverlayAlpha
    }

    private func updateFloatingHost() {
        let parent: UIView
        if let previewContainer {
            if floatingOverlay.superview !== previewContainer { previewContainer.addSubview(floatingOverlay) }
            floatingOverlay.frame = previewContainer.bounds
            updateFloatingVisibility()
            parent = floatingOverlay
        } else {
            floatingOverlay.removeFromSuperview()
            parent = self
        }
        for view in [positionGlass, preview] where view.superview !== parent {
            view.removeFromSuperview(); parent.addSubview(view)
        }
    }
    private func overlayPoint(_ point: CGPoint) -> CGPoint {
        guard let parent = preview.superview, parent !== self else { return point }
        return convert(point, to: parent)
    }
    private func overlayFrame(_ frame: CGRect) -> CGRect {
        guard let parent = positionGlass.superview, parent !== self else { return frame }
        return convert(frame, to: parent)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // The handoff snapshot is a sibling above the reader, not a child of
        // this control. Remove it explicitly when the reader leaves its window.
        if window == nil {
            panning = false; cancelPreview(); floatingOverlay.removeFromSuperview()
        } else { updateFloatingHost() }
    }

    func update(chapterKey: String, totalPages: Int, currentPage: Int, spreads: [[Int]]? = nil) {
        let updated = SumiScrubberPages(total: totalPages, spreads: spreads)
        let reported = min(max(1, currentPage), max(1, updated.total))
        if self.chapterKey == chapterKey { reportedCurrent = reported }
        if self.chapterKey == chapterKey, landing,
           model != updated || deferredModel != nil {
            // Loading a wide image can change pairing during preflight or
            // mounting. Preserve the pending canonical target and opaque handoff.
            deferredModel = updated
            return
        }
        let changed = self.chapterKey != chapterKey || model != updated
        if self.chapterKey != chapterKey || model.total != updated.total { deferredModel = nil }
        if changed {
            thumbnailRevision += 1
            interruptPreview()
            // An old gesture cannot keep ownership after its chapter or group
            // plan is replaced, even when both plans use the same cell pitch.
            stopStripMotion()
        }
        self.chapterKey = chapterKey; model = updated; reportedCurrent = reported
        if !landing { current = reported }
        isEnabled = !model.groups.isEmpty
        if changed || imagesSuspended { collection.reloadData() }
        if !scrubbing, !landing {
            let next = model.index(containing: current)
            let animate = !changed && !imagesSuspended && next != selectedGroup && !stripIsMoving && window != nil && !UIAccessibility.isReduceMotionEnabled
            selectedGroup = next
            refreshSelection(); needsPosition = !animate; setNeedsLayout()
            if animate { layoutIfNeeded(); positionSelection(animated: true) }
        }
        imagesSuspended = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let previewContainer { floatingOverlay.frame = previewContainer.bounds }
        let vertical = axis == .vertical
        let length = vertical ? bounds.height : bounds.width
        let thickness = min(SumiScrubberMetrics.railThickness, vertical ? bounds.width : bounds.height)
        rail.bounds = CGRect(x: 0, y: 0, width: length, height: thickness)
        rail.transform = vertical ? CGAffineTransform(rotationAngle: .pi / 2) : .identity
        rail.center = vertical ? CGPoint(x: bounds.midX, y: bounds.midY)
            : CGPoint(x: bounds.midX, y: bounds.maxY - thickness / 2)
        glass.frame = rail.bounds
        glassTint.frame = glass.bounds
        let stripFrame = glass.bounds.insetBy(dx: 8, dy: 0)
        if collection.frame != stripFrame { collection.frame = stripFrame }
        updateEdgeFade()
        if flow.configure(axis: axis, usesPairedPages: model.groups.contains { $0.count > 1 }) {
            // A real axis or grouping change gets one new canonical anchor.
            // Normal reader updates keep the exact active pan/coast offset.
            stopStripMotion()
            needsPosition = true
        }
        let inset = max(0, (collection.bounds.width - flow.pitch) / 2)
        if collection.contentInset.left != inset, !stripIsMoving, !landing {
            collection.contentInset = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
            flow.invalidateLayout(); needsPosition = true
        }
        if needsPosition, !scrubbing, !landing, !stripIsMoving { positionSelection(animated: false) }
        lens.frame = CGRect(x: rail.bounds.midX - flow.pitch / 2, y: 0, width: flow.pitch, height: thickness)
        if !landing { layoutHover() }
        let labelWidth = max(100, pageLabel.intrinsicContentSize.width + 24)
        let labelHeight = max(30, pageLabel.intrinsicContentSize.height + 8)
        let lifted = scrubbing || (landing && !lowering)
        let lensFrame = rail.convert(lens.frame, to: self)
        let labelFrame: CGRect
        if vertical {
            let x = sidebarEdge == .left ? lensFrame.maxX + SumiScrubberMetrics.badgeGap
                : lensFrame.minX - labelWidth - SumiScrubberMetrics.badgeGap
            labelFrame = CGRect(x: lifted ? hoverCenter.x - labelWidth / 2 : x,
                y: lifted ? hoverCenter.y - preview.bounds.height / 2 - labelHeight - SumiScrubberMetrics.badgeGap : bounds.midY - labelHeight / 2,
                width: labelWidth, height: labelHeight)
        } else {
            let width = min(max(1, bounds.width - 16), labelWidth)
            labelFrame = CGRect(x: bounds.midX - width / 2,
                y: (lifted ? hoverCenter.y - preview.bounds.height / 2 : lensFrame.minY) - labelHeight - SumiScrubberMetrics.badgeGap,
                width: width, height: labelHeight)
        }
        positionGlass.frame = fittedOverlayFrame(overlayFrame(labelFrame), preservesAspect: false)
        pageLabel.frame = positionGlass.bounds.insetBy(dx: 8, dy: 4)
        updateVisibleSelection()
    }

    private func positionSelection(animated: Bool) {
        guard !model.groups.isEmpty, collection.bounds.width > 0, !stripIsMoving, !landing else { return }
        collection.layoutIfNeeded()
        let offset = CGFloat(physicalIndex(for: selectedGroup)) * flow.pitch + flow.pitch / 2 - collection.bounds.width / 2
        collection.setContentOffset(CGPoint(x: offset, y: 0), animated: animated)
        needsPosition = false
    }
    private var stripIsMoving: Bool {
        panning || settling || collection.isTracking || collection.isDragging || collection.isDecelerating
    }
    private func stopStripMotion() {
        panning = false; settling = false
        collection.setContentOffset(collection.contentOffset, animated: false)
        collection.panGestureRecognizer.isEnabled = false
        collection.panGestureRecognizer.isEnabled = true
    }
    private func physicalIndex(for logical: Int) -> Int { isReversed ? max(0, model.groups.count - 1 - logical) : logical }
    private func logicalIndex(for physical: Int) -> Int { isReversed ? model.groups.count - 1 - physical : physical }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { model.groups.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SumiPageThumbnailCell.reuseID, for: indexPath)
        if let cell = cell as? SumiPageThumbnailCell {
            let logical = logicalIndex(for: indexPath.item)
            cell.isVertical = axis == .vertical
            cell.onPreviewReady = { [weak self] ready in
                guard let self, selectedGroup == logical else { return }
                lens.accessibilityValue = ready ? "Preview ready" : "Preview unavailable"
            }
            cell.configure(chapterKey: thumbnailIdentity, group: logical, pages: model.groups[logical], reversed: reversesThumbnailPages, provider: imageProvider)
            cell.updateSelection(logical == selectedGroup)
        }
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        beginPreview(); setPreview(group: logicalIndex(for: indexPath.item))
        let point = CGPoint(x: CGFloat(indexPath.item) * flow.pitch + flow.pitch / 2 - collectionView.bounds.width / 2, y: 0)
        settleStrip(at: point)
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        panning = true
        beginPreview()
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateEdgeFade()
        guard scrubbing, !model.groups.isEmpty else { updateVisibleSelection(); return }
        let physical = Int(((scrollView.contentOffset.x + scrollView.bounds.width / 2 - flow.pitch / 2) / flow.pitch).rounded())
        setPreview(group: logicalIndex(for: min(max(0, physical), model.groups.count - 1)))
    }

    private func updateEdgeFade() {
        // The rail rotates as one unit for a sidebar. Its local scroll axis
        // remains horizontal, so this also fades the physical top and bottom.
        let fraction = min(0.45, 12 / max(1, collection.bounds.width))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeFade.frame = collection.bounds
        edgeFade.locations = [0, NSNumber(value: Double(fraction)), NSNumber(value: Double(1 - fraction)), 1]
        CATransaction.commit()
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        panning = false
        // UICollectionView's targetContentOffset owns a decelerating release.
        // A slow release needs the same animated finish, never a hard recenter.
        if !decelerate { settleStrip() }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settleStrip() }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard settling else { return }
        settling = false
        landAfterIdle()
    }
    private func settleStrip(at requested: CGPoint? = nil) {
        guard scrubbing, !panning, !collection.isDragging else { setNeedsLayout(); return }
        let point = requested ?? flow.targetContentOffset(forProposedContentOffset: collection.contentOffset, withScrollingVelocity: .zero)
        if abs(collection.contentOffset.x - point.x) > 0.5 {
            settling = true
            collection.setContentOffset(point, animated: true)
        } else { landAfterIdle() }
    }
    private func landAfterIdle() {
        settleTask?.cancel()
        let id = token
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(32))
            guard !Task.isCancelled, let self, token == id, !stripIsMoving else { return }
            finishPreview(commit: true)
        }
    }

    private func beginPreview() {
        let visible = !preview.isHidden
        let layer = preview.layer.presentation() ?? preview.layer
        let position = layer.position, transform = layer.transform, opacity = layer.opacity
        interruptPreview(keepingSnapshot: isRecoveringSnapshot)
        token = UUID(); scrubbing = true
        needsPosition = false
        feedback.prepare()
        preview.isHidden = false; layoutHover()
        configureHover(pages: model.groups[safe: selectedGroup] ?? [])
        preview.layer.transform = visible ? transform : CATransform3DMakeScale(0.2, 0.2, 1)
        preview.center = visible ? position : overlayPoint(rail.convert(CGPoint(x: lens.frame.midX, y: lens.frame.midY), to: self))
        preview.alpha = visible ? CGFloat(opacity) : 1
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.25, delay: 0,
                       usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.preview.layer.transform = CATransform3DIdentity; self.preview.center = self.overlayPoint(self.hoverCenter); self.preview.alpha = 1
        }
        setNeedsLayout()
    }
    private func layoutHover() {
        let count = preview.displayedPages.isEmpty ? model.groups[safe: selectedGroup]?.count ?? 0 : preview.displayedPages.count
        let paired = count > 1
        let available = previewContainer?.bounds.size ?? window?.bounds.size ?? CGSize(width: 466, height: 678)
        let height = SumiScrubberMetrics.hoverHeight(in: available)
        let width = height * SumiScrubberMetrics.pageAspect * (paired ? 2 : 1)
        preview.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let lensFrame = rail.convert(lens.frame, to: self)
        if axis == .vertical {
            hoverCenter = CGPoint(x: sidebarEdge == .left ? lensFrame.maxX + SumiScrubberMetrics.hoverGap + width / 2
                : lensFrame.minX - SumiScrubberMetrics.hoverGap - width / 2, y: bounds.midY)
        } else {
            hoverCenter = CGPoint(x: bounds.midX, y: lensFrame.minY - SumiScrubberMetrics.hoverGap - height / 2)
        }
        if previewContainer != nil {
            let preferred = CGRect(x: overlayPoint(hoverCenter).x - width / 2,
                y: overlayPoint(hoverCenter).y - height / 2, width: width, height: height)
            let fitted = fittedOverlayFrame(preferred, preservesAspect: true)
            preview.bounds.size = fitted.size
            if let parent = preview.superview {
                hoverCenter = convert(CGPoint(x: fitted.midX, y: fitted.midY), from: parent)
            }
        }
        preview.layer.shadowPath = UIBezierPath(roundedRect: preview.bounds,
            cornerRadius: SumiScrubberMetrics.previewCornerRadius).cgPath
        if preview.isHidden { preview.center = overlayPoint(hoverCenter) }
    }

    private func fittedOverlayFrame(_ preferred: CGRect, preservesAspect: Bool) -> CGRect {
        guard let container = previewContainer else { return preferred }
        var insets = container.safeAreaInsets
        if axis == .vertical {
            // Floating controls belong to the status rail. Applying that rail's
            // content inset again would push the badge away from its strip.
            if sidebarEdge == .left { insets.left = 0 }
            else { insets.right = 0 }
        }
        var bounds = container.bounds.inset(by: UIEdgeInsets(top: max(8, insets.top),
            left: max(8, insets.left), bottom: max(8, insets.bottom), right: max(8, insets.right)))
        let anchor = rail.convert(lens.frame, to: container)
        if preservesAspect {
            // Reserve space above the floating print for its page badge, and
            // keep the preview inward of its strip even in a narrow pane.
            let badgeHeight = max(30, pageLabel.intrinsicContentSize.height + 8)
            bounds.origin.y += badgeHeight + SumiScrubberMetrics.badgeGap
            bounds.size.height = max(1, bounds.height - badgeHeight - SumiScrubberMetrics.badgeGap)
            if axis == .vertical {
                if sidebarEdge == .left {
                    let leading = max(bounds.minX, anchor.maxX + SumiScrubberMetrics.hoverGap)
                    bounds = CGRect(x: leading, y: bounds.minY, width: max(1, bounds.maxX - leading), height: bounds.height)
                } else {
                    bounds.size.width = max(1, min(bounds.maxX, anchor.minX - SumiScrubberMetrics.hoverGap) - bounds.minX)
                }
            } else {
                bounds.size.height = max(1, min(bounds.maxY, anchor.minY - SumiScrubberMetrics.hoverGap) - bounds.minY)
            }
        }
        var exclusions: [CGRect] = []
        if #available(iOS 27.1, *) {
            exclusions = (container.reservedRegions(kind: .division) + container.reservedRegions(kind: .occlusion))
                .filter(\.isActive).map(\.frame)
        }
        return SumiScrubberOverlayLayout.frame(preferred, anchor: anchor, in: bounds,
            avoiding: exclusions, preservesAspect: preservesAspect)
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        if pan.state == .cancelled || pan.state == .failed { panning = false; cancelPreview() }
    }
    private func updateVisibleSelection() {
        for case let cell as SumiPageThumbnailCell in collection.visibleCells { cell.updateSelection(cell.group == selectedGroup) }
        if let cell = collection.cellForItem(at: IndexPath(item: physicalIndex(for: selectedGroup), section: 0)) as? SumiPageThumbnailCell {
            lens.accessibilityValue = cell.previewReady ? "Preview ready" : cell.accessibilityValue
        }
    }
    private func refreshSelection() {
        let text = model.label(for: selectedGroup)
        pageLabel.text = text; accessibilityValue = text
        let pages = model.groups[safe: selectedGroup] ?? []
        lens.accessibilityLabel = pages.count == 2 ? "Pages \(pages[0]) and \(pages[1])" : "Page \(pages.first ?? 1)"
        lens.accessibilityValue = "Loading preview"
        updateVisibleSelection()
    }
    private func setPreview(group: Int) {
        guard isEnabled, model.groups.indices.contains(group) else { return }
        if !scrubbing { beginPreview() }
        guard selectedGroup != group else { return }
        selectedGroup = group; feedback.selectionChanged(); feedback.prepare()
        refreshSelection(); layoutHover()
        configureHover(pages: model.groups[group])
        setNeedsLayout()
    }
    private func configureHover(pages: [Int]) {
        preview.configure(identity: thumbnailIdentity, pages: pages, reversed: reversesThumbnailPages,
                          preservingCurrent: true, provider: hoverImageProvider ?? imageProvider) { [weak self] _ in
            self?.setNeedsLayout()
        }
    }
    func preview(at point: CGPoint) {
        layoutIfNeeded()
        let local = rail.convert(point, from: self)
        let fraction = min(1, max(0, (local.x - 14) / max(1, rail.bounds.width - 28)))
        setPreview(group: Int(((isReversed ? 1 - fraction : fraction) * CGFloat(max(0, model.groups.count - 1))).rounded()))
    }
    func finishPreview(commit: Bool) {
        guard scrubbing else { return }
        if !commit { cancelPreview(); return }
        let pages = model.groups[safe: selectedGroup] ?? []
        let number = pages.contains(current) ? current : pages.first ?? current
        let changed = number != current
        guard !panning else { return }
        scrubbing = false; settleTask?.cancel()
        let id = token
        // The strip is already at its native landing position. Re-centering
        // here races asynchronous preparation and interrupts the final frames.
        needsPosition = false; setNeedsLayout()
        if changed { prepareAndCommit(number, id: id) }
        else { lowerPreview(id: id) }
    }
    private func prepareAndCommit(_ number: Int, id: UUID) {
        if let preparePage {
            landing = true
            landingTask = Task { [weak self] in
                let prepared = await preparePage(number)
                guard !Task.isCancelled, let self, token == id else { return }
                guard prepared else { cancelPreview(keepingSnapshot: isRecoveringSnapshot); return }
                commitPreparedPage(number, id: id)
            }
        } else { commitPreparedPage(number, id: id) }
    }
    private func commitPreparedPage(_ number: Int, id: UUID) {
        guard token == id else { return }
        landing = true
        if let navigateToPage {
            // A page curl must stay visible. Do not cover it with the old
            // immutable raster used by the nonanimated legacy handoff.
            landingBackdrop?.removeFromSuperview(); landingBackdrop = nil
            isRecoveringSnapshot = false; navigating = true; lowering = true
            lowerHoverForNavigation()
            landingTask = Task { [weak self] in
                let completed = await navigateToPage(number)
                guard !Task.isCancelled, let self, token == id else { return }
                navigating = false
                current = completed && deferredModel == nil ? number : reportedCurrent
                selectedGroup = model.index(containing: current)
                refreshSelection()
                if !completed { needsPosition = true }
                clearLanding()
            }
            return
        }
        let previousPage = current
        isRecoveringSnapshot = false
        if landingBackdrop == nil, let surface = landingSurface?(), let snapshot = rasterSnapshot(of: surface) {
            snapshot.frame = surface.frame
            snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            snapshot.isUserInteractionEnabled = false
            snapshot.accessibilityElementsHidden = true
            snapshot.accessibilityIdentifier = "Sumi.Reader.ScrubHandoff"
            surface.superview?.insertSubview(snapshot, aboveSubview: surface)
            landingBackdrop = snapshot
        }
        current = number; refreshSelection(); onCommit?(number)
        guard token == id else { return }
        guard landingBackdrop != nil else { lowerPreview(id: id); return }
        landingTask = Task { [weak self] in
            // Preflight has loaded every destination leaf. Keep the old actual
            // reader opaque until the mounted destination has also laid out.
            // Never enlarge a low-resolution hover image over the whole screen.
            guard !Task.isCancelled, let self, token == id else { return }
            if !(await waitForDestination(number, id: id)) {
                guard !Task.isCancelled, token == id else { return }
                await restorePreviousPage(previousPage, id: id)
                return
            }
            guard !Task.isCancelled, token == id else { return }
            landingSurface?()?.layoutIfNeeded()
            UIView.performWithoutAnimation {
                landingBackdrop?.removeFromSuperview(); landingBackdrop = nil
            }
            lowerPreview(id: id)
        }
    }
    private func waitForDestination(_ page: Int, id: UUID) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            guard !Task.isCancelled, token == id else { return false }
            if isLandingReady?(page) ?? true {
                landingSurface?()?.layoutIfNeeded()
                let rendered = await SumiReaderFrameFence.wait()
                guard !Task.isCancelled, token == id else { return false }
                if rendered, isLandingReady?(page) ?? true { return true }
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
        return false
    }
    private func rasterSnapshot(of surface: UIView) -> UIImageView? {
        guard surface.bounds.width > 0, surface.bounds.height > 0 else { return nil }
        surface.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = surface.traitCollection.displayScale
        format.opaque = true
        // Freeze pixels synchronously before mounting either new leaf. UIKit's
        // lazy snapshot view can otherwise capture a partially changed spread.
        let image = UIGraphicsImageRenderer(bounds: surface.bounds, format: format).image { context in
            surface.layer.render(in: context.cgContext)
        }
        let snapshot = UIImageView(image: image)
        snapshot.isOpaque = true
        snapshot.alpha = 1
        snapshot.contentMode = .scaleToFill
        return snapshot
    }
    private func restorePreviousPage(_ page: Int, id: UUID) async {
        _ = await preparePage?(page)
        guard !Task.isCancelled, token == id else { return }
        current = page
        if let deferredModel {
            model = deferredModel; self.deferredModel = nil
            thumbnailRevision += 1
            collection.reloadData()
        }
        selectedGroup = model.index(containing: page)
        refreshSelection(); needsPosition = true; setNeedsLayout()
        onCommit?(page)
        guard !Task.isCancelled, token == id else { return }
        // A pose change can cancel preflight while the rollback itself still
        // mounts a complete surface. Actual visible readiness is authoritative.
        let restored = await waitForDestination(page, id: id)
        guard !Task.isCancelled, token == id else { return }
        // A failed recovery must not uncover a blank destination. The owned
        // snapshot remains a stable old-page fallback until the next action.
        isRecoveringSnapshot = !restored
        lowerPreview(id: id, keepingSnapshot: !restored)
    }
    private func lowerHoverForNavigation() {
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.18, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.preview.layer.transform = CATransform3DMakeScale(0.2, 0.2, 1)
            self.preview.center = self.overlayPoint(self.rail.convert(CGPoint(x: self.lens.frame.midX, y: self.lens.frame.midY), to: self))
            self.preview.alpha = 0
            self.setNeedsLayout(); self.layoutIfNeeded()
        }
    }

    private func lowerPreview(id: UUID, keepingSnapshot: Bool = false) {
        landing = true; lowering = true
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.25, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.preview.layer.transform = CATransform3DMakeScale(0.2, 0.2, 1)
            self.preview.center = self.overlayPoint(self.rail.convert(CGPoint(x: self.lens.frame.midX, y: self.lens.frame.midY), to: self))
            self.preview.alpha = 0
            self.setNeedsLayout(); self.layoutIfNeeded()
        } completion: { [weak self] _ in
            guard let self, token == id else { return }; clearLanding(keepingSnapshot: keepingSnapshot)
        }
    }
    private func clearLanding(keepingSnapshot: Bool = false) {
        landing = false; lowering = false; preview.isHidden = true; preview.alpha = 1; preview.layer.transform = CATransform3DIdentity
        if !keepingSnapshot {
            landingBackdrop?.removeFromSuperview(); landingBackdrop = nil; isRecoveringSnapshot = false
        }
        if let deferredModel {
            model = deferredModel; self.deferredModel = nil
            thumbnailRevision += 1
            selectedGroup = model.index(containing: current)
            collection.reloadData(); needsPosition = true; refreshSelection()
        }
        preview.cancelImage(); setNeedsLayout()
    }
    func interruptPreview(keepingSnapshot: Bool = false) {
        if navigating { current = reportedCurrent }
        navigating = false
        token = UUID(); settleTask?.cancel(); landingTask?.cancel()
        settling = false
        preview.layer.removeAllAnimations(); clearLanding(keepingSnapshot: keepingSnapshot); scrubbing = false
    }
    func cancelPreview(keepingSnapshot: Bool = false) {
        interruptPreview(keepingSnapshot: keepingSnapshot)
        selectedGroup = model.index(containing: current); needsPosition = true
        refreshSelection(); setNeedsLayout()
    }
    func suspendImages() {
        panning = false
        cancelPreview()
        for case let cell as SumiPageThumbnailCell in collection.visibleCells { cell.cancelImage() }
        imagesSuspended = true
    }
    override func accessibilityIncrement() { _ = accessibilityMove(1) }
    override func accessibilityDecrement() { _ = accessibilityMove(-1) }
    @discardableResult private func accessibilityMove(_ delta: Int) -> Bool {
        guard isEnabled else { return false }
        cancelPreview()
        let index = min(max(0, model.index(containing: current) + delta), model.groups.count - 1)
        let number = model.groups[index].first ?? current
        selectedGroup = index; refreshSelection(); needsPosition = true; setNeedsLayout()
        if preparePage != nil || navigateToPage != nil { prepareAndCommit(number, id: token) }
        else { current = number; onCommit?(current) }
        return true
    }
}
#endif
