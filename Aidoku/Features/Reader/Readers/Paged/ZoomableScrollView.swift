//
//  ZoomableScrollView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/22/21.
//
//  Copyright © 2018 Seyed Samad Gholamzadeh. All rights reserved.
//  https://github.com/ssamadgh/PhotoScroller_Completed_Sample_Code_Part_I/blob/master/PhotoScroller/ImageScrollView.swift
//

import UIKit

class ZoomableScrollView: UIScrollView {
    var zoomView: UIView? {
        didSet {
            configure()
        }
    }

    var zoomEnabled = true {
        didSet {
            updateInteraction()
        }
    }

    var onZoomScaleChanged: ((CGFloat) -> Void)?
    /// The unzoomed image (or spread) frame in `zoomView` coordinates.
    var pageContentFrame: (() -> CGRect?)?
    private(set) var baselineZoomScale: CGFloat = 1
    private var pageSizing = AppSettings.reader.pageSizing.get()
    /// A reader container can choose sizing from its full viewport rather than
    /// from an individual leaf or a persisted user preference.
    var pageSizingOverride: ReaderPageSizing? {
        didSet {
            guard pageSizingOverride != oldValue else { return }
            applyPageSizing(AppSettings.reader.pageSizing.get(), resetZoom: true)
        }
    }
    var effectivePageSizing: ReaderPageSizing { pageSizing }
    private var lastSizingGeometry: ReaderPageSizingGeometry?
    private var resetsPageSizing = false
    private var isUpdatingPageSizing = false
    private var isUpdatingWidthViewport = false
    private var viewportCenter = CGPoint(x: 0.5, y: 0.5)
    private var widthReadingPosition: CGFloat = 0
    private var pageSizingObserver: NSObjectProtocol?
    private var allowsDoubleTap = true

    var doubleTapEnabled: Bool {
        get { zoomingTap.isEnabled }
        set {
            allowsDoubleTap = newValue
            updateInteraction()
        }
    }

    private lazy var zoomingTap: UITapGestureRecognizer = {
        let zoomingTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        zoomingTap.numberOfTapsRequired = 2
        return zoomingTap
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        delegate = self
        maximumZoomScale = 5
        minimumZoomScale = 1
        bouncesZoom = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        insetsLayoutMarginsFromSafeArea = false
        contentInsetAdjustmentBehavior = .never
        updateInteraction()

        pageSizingObserver = NotificationCenter.default.addObserver(
            forName: .init(AppSettings.reader.pageSizing.key), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyPageSizing(AppSettings.reader.pageSizing.get(), resetZoom: true)
            }
        }

        if #available(iOS 27.0, *) {
            #if SUMI
            topEdgeEffect.isHidden = true
            bottomEdgeEffect.isHidden = true
            leftEdgeEffect.isHidden = true
            rightEdgeEffect.isHidden = true
            #else
            topEdgeEffect.style = .soft
            bottomEdgeEffect.style = .soft
            #endif
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let pageSizingObserver {
            NotificationCenter.default.removeObserver(pageSizingObserver)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePageSizing()
        centerView()
    }

    func applyPageSizing(_ sizing: ReaderPageSizing, resetZoom: Bool) {
        let resolvedSizing = pageSizingOverride ?? sizing
        let changedSizing = pageSizing != resolvedSizing
        pageSizing = resolvedSizing
        updateInteraction()
        updatePageSizing(resetZoom: resetZoom || changedSizing)
        setNeedsLayout()
    }

    private func updateInteraction() {
        #if SUMI
        let allowsZoom = false
        #else
        let allowsZoom = zoomEnabled && pageSizing == .fit
        #endif
        isScrollEnabled = zoomEnabled
        panGestureRecognizer.isEnabled = zoomEnabled
        pinchGestureRecognizer?.isEnabled = allowsZoom
        zoomingTap.isEnabled = allowsZoom && allowsDoubleTap
        isDirectionalLockEnabled = pageSizing == .fill
        bounces = true
        alwaysBounceHorizontal = false
        if pageSizing == .fit {
            alwaysBounceVertical = false
        }
        bouncesZoom = allowsZoom
    }

    func updatePageSizing(resetZoom: Bool = false) {
        resetsPageSizing = resetsPageSizing || resetZoom
        guard
            !isUpdatingPageSizing,
            let zoomView, let pageFrame = pageContentFrame?(),
            let geometry = ReaderPageSizingGeometry(
                viewportSize: bounds.size, contentSize: zoomView.bounds.size, pageFrame: pageFrame
            )
        else { return }
        let baseline = geometry.baselineScale(for: pageSizing)
        guard resetsPageSizing || geometry != lastSizingGeometry || baseline != baselineZoomScale else { return }

        isUpdatingPageSizing = true
        defer {
            isUpdatingPageSizing = false
            if pageSizing == .fill {
                updateWidthReadingPosition()
            } else {
                updateViewportCenter()
            }
        }
        let wasAtBaseline = abs(zoomScale - baselineZoomScale) < 0.001
        let resetsReadingPosition = resetsPageSizing || lastSizingGeometry == nil
        let resetsZoom = pageSizing == .fill || resetsPageSizing || lastSizingGeometry == nil || wasAtBaseline
        let center = resetsZoom ? CGPoint(x: 0.5, y: 0.5) : viewportCenter
        let scale = pageSizing == .fill ? baseline : resetsZoom ? 1 : min(max(zoomScale, 1), 5)
        baselineZoomScale = baseline
        lastSizingGeometry = geometry
        resetsPageSizing = false
        if pageSizing == .fit {
            contentInset = .zero
        }
        let minimumScale: CGFloat = pageSizing == .fill ? baseline : 1
        #if SUMI
        let maximumScale: CGFloat = minimumScale
        #else
        let maximumScale: CGFloat = pageSizing == .fill ? baseline : 5
        #endif
        // Widen the old limits before setting the new scale, then lock width
        // mode to it. Fit mode keeps its normal pinch and double-tap range.
        minimumZoomScale = min(minimumZoomScale, minimumScale)
        maximumZoomScale = max(maximumZoomScale, maximumScale)
        setZoomScale(scale, animated: false)
        minimumZoomScale = minimumScale
        maximumZoomScale = maximumScale
        centerView()
        if pageSizing == .fill {
            configureWidthViewport(readingPosition: resetsReadingPosition ? 0 : widthReadingPosition)
        } else {
            positionPage(at: center, geometry: geometry)
        }
    }

    private func updateViewportCenter() {
        guard let zoomView, let geometry = lastSizingGeometry,
              geometry.viewportSize == bounds.size, geometry.contentSize == zoomView.bounds.size,
              geometry.pageFrame == pageContentFrame?() else { return }
        let center = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: zoomView)
        viewportCenter = CGPoint(
            x: min(max((center.x - geometry.pageFrame.minX) / geometry.pageFrame.width, 0), 1),
            y: min(max((center.y - geometry.pageFrame.minY) / geometry.pageFrame.height, 0), 1)
        )
    }

    /// Called only when sizing geometry changes or the user explicitly resets it.
    /// Scroll callbacks must not reposition content or rewrite insets: doing so
    /// interrupts UIScrollView's own deceleration and rubber-band return.
    private func configureWidthViewport(readingPosition: CGFloat) {
        guard !isUpdatingWidthViewport, let zoomView,
              let geometry = lastSizingGeometry, geometry.viewportSize == bounds.size,
              geometry.contentSize == zoomView.bounds.size, geometry.pageFrame == pageContentFrame?() else { return }
        let frame = zoomView.convert(geometry.pageFrame, to: self)
        let x = frame.midX - bounds.width / 2
        let isTall = frame.height > bounds.height
        let minimumY = isTall ? frame.minY : frame.midY - bounds.height / 2
        let maximumY = isTall ? frame.maxY - bounds.height : minimumY
        alwaysBounceVertical = isTall
        let insets = UIEdgeInsets(
            top: -minimumY,
            left: -x,
            bottom: maximumY + bounds.height - contentSize.height,
            right: x + bounds.width - contentSize.width
        )
        isUpdatingWidthViewport = true
        defer { isUpdatingWidthViewport = false }
        if contentInset != insets {
            contentInset = insets
        }
        let proposedY = frame.minY + frame.height * readingPosition
        let y = min(max(proposedY, minimumY), maximumY)
        let offset = CGPoint(x: x, y: y)
        if abs(offset.x - contentOffset.x) > 0.001 || abs(offset.y - contentOffset.y) > 0.001 {
            setContentOffset(offset, animated: false)
        }
    }

    private func updateWidthReadingPosition() {
        guard !isUpdatingWidthViewport, let zoomView, let geometry = lastSizingGeometry,
              geometry.viewportSize == bounds.size, geometry.contentSize == zoomView.bounds.size,
              geometry.pageFrame == pageContentFrame?() else { return }
        let frame = zoomView.convert(geometry.pageFrame, to: self)
        // A transient bounce must not become the saved position after a fold.
        let maximumTop = max(frame.minY, frame.maxY - bounds.height)
        let y = min(max(contentOffset.y, frame.minY), maximumTop)
        widthReadingPosition = (y - frame.minY) / frame.height
    }

    private func positionPage(at center: CGPoint, geometry: ReaderPageSizingGeometry) {
        guard let zoomView else { return }
        let frame = geometry.pageFrame
        let point = zoomView.convert(CGPoint(x: frame.minX + frame.width * center.x, y: frame.minY + frame.height * center.y), to: self)
        let minimumOffset = CGPoint(x: -adjustedContentInset.left, y: -adjustedContentInset.top)
        let offset = CGPoint(
            x: min(max(point.x - bounds.width / 2, minimumOffset.x), max(minimumOffset.x, contentSize.width - bounds.width + adjustedContentInset.right)),
            y: min(max(point.y - bounds.height / 2, minimumOffset.y), max(minimumOffset.y, contentSize.height - bounds.height + adjustedContentInset.bottom))
        )
        guard abs(offset.x - contentOffset.x) > 0.001 || abs(offset.y - contentOffset.y) > 0.001 else { return }
        setContentOffset(offset, animated: false)
    }

    /// An unzoomed Fit page has no sideways content to drag. Yield that pan
    /// to the native pager, while retaining real zoomed panning and pinching.
    func permitsPagePan(velocity: CGPoint, touchCount: Int = 1) -> Bool {
        guard abs(velocity.x) > abs(velocity.y) else { return true }
        if pageSizing == .fill { return false }
        guard touchCount <= 1, !isZooming else { return true }
        let range = max(0, contentSize.width + adjustedContentInset.left + adjustedContentInset.right - bounds.width)
        let pixel = 1 / max(1, traitCollection.displayScale)
        return range > pixel
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer,
           !permitsPagePan(velocity: panGestureRecognizer.velocity(in: self), touchCount: panGestureRecognizer.numberOfTouches) {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func configure() {
        zoomView?.addGestureRecognizer(zoomingTap)
        zoomView?.isUserInteractionEnabled = true
    }

    func centerView() {
        guard pageSizing == .fit, let zoomView else { return }
        // The zoomed view's frame is managed by UIScrollView and its content
        // guides. Mutating that transformed frame conflicts with Auto Layout
        // during a fold. Center smaller content using scroll insets instead.
        let horizontal = max(0, (bounds.width - zoomView.bounds.width * zoomScale) / 2)
        let vertical = max(0, (bounds.height - zoomView.bounds.height * zoomScale) / 2)
        let insets = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != insets {
            contentInset = insets
        }
    }
}

// MARK: - Double Tap Gesture
extension ZoomableScrollView {
    @objc func handleDoubleTap(_ sender: UITapGestureRecognizer) {
        guard zoomEnabled else { return }
        let location = sender.location(in: sender.view)
        zoom(to: location, animated: true)
    }

    func zoom(to point: CGPoint, animated: Bool) {
        #if SUMI
        return
        #else
        guard zoomEnabled, pageSizing == .fit else { return }
        let currentScale = self.zoomScale
        let minScale = self.minimumZoomScale
        let maxScale = self.maximumZoomScale

        if minScale == maxScale && minScale > 1 {
            return
        }

        let finalScale = abs(currentScale - baselineZoomScale) < 0.001
            ? min(maxScale, baselineZoomScale * 2) : baselineZoomScale
        let zoomRect = zoomRect(for: finalScale, withCenter: point)
        zoom(to: zoomRect, animated: animated)
        #endif
    }

    func zoomRect(for scale: CGFloat, withCenter center: CGPoint) -> CGRect {
        var zoomRect = CGRect.zero
        let bounds = self.bounds

        zoomRect.size.width = bounds.size.width / scale
        zoomRect.size.height = bounds.size.height / scale

        zoomRect.origin.x = center.x - (zoomRect.size.width / 2)
        zoomRect.origin.y = center.y - (zoomRect.size.height / 2)

        return zoomRect
    }
}

// MARK: - Scroll View Delegate
extension ZoomableScrollView: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        zoomView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerView()
        if !isUpdatingPageSizing && !isUpdatingWidthViewport {
            if pageSizing == .fill {
                updateWidthReadingPosition()
            } else {
                updateViewportCenter()
            }
        }
        onZoomScaleChanged?(zoomScale)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if !isUpdatingPageSizing && !isUpdatingWidthViewport {
            if pageSizing == .fill {
                updateWidthReadingPosition()
            } else {
                updateViewportCenter()
            }
        }
    }
}
