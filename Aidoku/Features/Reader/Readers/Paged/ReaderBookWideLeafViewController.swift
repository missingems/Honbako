import Gifu
import UIKit
import VisionKit

/// Displays half of the SAME original image without creating a Page or writing
/// derived content into the canonical image/OCR store.
final class ReaderBookWideLeafViewController: BaseObservingViewController {
    enum Side { case left, right }
    let canonicalController: ReaderPageViewController
    let side: Side
    let zoomView = ZoomableScrollView(frame: .zero)
    let imageView = GIFImageView()
    #if SUMI
    var sumiPageSizing: ReaderPageSizing? = .fit {
        didSet { zoomView.pageSizingOverride = sumiPageSizing }
    }
    var bookBindingEdge: ReaderBookSpineView.BindingEdge = .none {
        didSet { if isViewLoaded { updatePaperShape() } }
    }
    private let paperMask = CAShapeLayer()
    private let sumiLoadingView = SumiPageImageLoadingView()
    private let sumiEdgeBackground = SumiPageEdgeBackgroundView()
    var sumiIsImageReady: Bool {
        imageView.image != nil && !sumiLoadingView.isRevealing && imageView.alpha > 0.99 && sumiEdgeBackground.isReady
    }

    func sumiRevealAfterLoadingPlaceholder() {
        guard imageView.image != nil else { return }
        sumiLoadingView.reveal(imageView, animated: view.window != nil)
    }
    #endif
    private var referenceGIFData: Data?
    private var isVisible = false
    private lazy var gifFrameMirror = ReaderBookGIFFrameMirror(imageView: imageView)
    private let canvas = UIView()
    private let texture = ReaderPaperTextureView()
    private let overlayView = DictionaryOverlayPassthroughView()
    private let overlays = DictionaryOverlayController()
    private var dictionaryOverlaysDirty = true
    private var shouldShowLiveTextButton = false
    private var _liveTextInteraction: Any?
    @available(iOS 16.0, *)
    private var liveTextInteraction: ImageAnalysisInteraction? { _liveTextInteraction as? ImageAnalysisInteraction }
    var onDictionaryLookup: ((String, String, CGRect, [CGRect]) -> Void)? {
        didSet { overlays.onLookup = onDictionaryLookup }
    }
    var dictionaryInteractionMode: DictionaryOverlayInteractionMode = .none {
        didSet { overlays.interactionMode = dictionaryInteractionMode; refreshDictionaryOverlays() }
    }

    var canonicalImageRect: CGRect {
        guard let image = imageView.image else { return .zero }
        return CGRect(x: side == .left ? 0 : image.size.width / 2, y: 0, width: image.size.width / 2, height: image.size.height)
    }

    init(canonicalController: ReaderPageViewController, side: Side) {
        self.canonicalController = canonicalController
        self.side = side
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func configure() {
        #if SUMI
        view.backgroundColor = SumiPaperSurface.backgroundColor
        sumiEdgeBackground.frame = view.bounds
        sumiEdgeBackground.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(sumiEdgeBackground)
        #endif
        view.clipsToBounds = true
        // Native center-spine leaves can end on a half point. Keep the exact
        // viewport instead of independently rounding each leaf to a pixel.
        zoomView.frame = view.bounds
        zoomView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(zoomView)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.clipsToBounds = true
        zoomView.addSubview(canvas)
        imageView.isUserInteractionEnabled = true
        imageView.contentMode = .scaleAspectFit
        #if !SUMI
        if #available(iOS 16.0, *), UserDefaults.standard.bool(forKey: "Reader.liveText"), ImageAnalyzer.isSupported {
            let interaction = ImageAnalysisInteraction()
            interaction.preferredInteractionTypes = .automatic
            imageView.addInteraction(interaction)
            _liveTextInteraction = interaction
        }
        #endif
        canvas.addSubview(imageView)
        #if SUMI
        sumiLoadingView.frame = view.bounds
        sumiLoadingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(sumiLoadingView, belowSubview: zoomView)
        view.insertSubview(sumiEdgeBackground, aboveSubview: sumiLoadingView)
        #endif
        imageView.addSubview(texture)
        imageView.addSubview(overlayView)
        overlayView.backgroundColor = .clear
        overlays.containerView = overlayView
        overlays.onLookup = onDictionaryLookup
        zoomView.zoomView = canvas
        zoomView.pageContentFrame = { [weak self] in self?.drawnHalfFrame() }
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: zoomView.contentLayoutGuide.leadingAnchor), canvas.trailingAnchor.constraint(equalTo: zoomView.contentLayoutGuide.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: zoomView.contentLayoutGuide.topAnchor), canvas.bottomAnchor.constraint(equalTo: zoomView.contentLayoutGuide.bottomAnchor),
            canvas.widthAnchor.constraint(equalTo: zoomView.frameLayoutGuide.widthAnchor), canvas.heightAnchor.constraint(equalTo: zoomView.frameLayoutGuide.heightAnchor)
        ])
        refreshImage()
    }

    override func observe() {
        for key in ["Reader.disableDoubleTap", AppSettings.dictionary.enable.key,
                    AppSettings.dictionary.lookupGesture.key, AppSettings.dictionary.textOverlayMode.key,
                    AppSettings.dictionary.restrictOCRLanguages.key, AppSettings.dictionary.restrictedOCRLanguages.key] {
            addObserver(forName: key) { [weak self] _ in
                self?.updateDoubleTapSetting()
                self?.refreshDictionaryOverlays()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if zoomView.frame != view.bounds { zoomView.frame = view.bounds }
        if view.window != nil {
            canonicalController.pageView?.updateReferenceViewport(
                width: view.bounds.width * 2, displayScale: traitCollection.displayScale
            )
        }
        layoutOriginalImage()
        zoomView.updatePageSizing()
        #if SUMI
        updatePaperShape()
        #endif
    }

    #if SUMI
    func updatePaperShape() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if bookBindingEdge == .none {
            ReaderBookSpineView.removeBindingLighting(from: view.layer)
            view.layer.shadowOpacity = 0
            view.layer.shadowPath = nil
        }
        paperMask.frame = view.bounds
        paperMask.path = ReaderBookSpineView.pagePath(in: view.bounds, bindingEdge: bookBindingEdge)
        view.layer.mask = paperMask
        CATransaction.commit()
    }
    #endif

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        updateGIFMirroring()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isVisible = false
        gifFrameMirror.stop()
    }

    private func updateGIFMirroring() {
        if referenceGIFData != nil, isVisible {
            gifFrameMirror.start()
        } else {
            gifFrameMirror.stop()
        }
    }

    private func originalFrame() -> CGRect {
        guard let image = imageView.image else { return .zero }
        // The parent leaf is authoritative: the canvas can still have its old
        // layout-guide size while a native page controller is being attached.
        let size = CGSize(width: view.bounds.width * 2, height: view.bounds.height)
        return ReaderPageSizingGeometry.aspectFitFrame(imageSize: image.size, in: CGRect(origin: .zero, size: size))
            .offsetBy(dx: side == .left ? 0 : -view.bounds.width, dy: 0)
    }

    private func drawnHalfFrame() -> CGRect? {
        let original = originalFrame()
        let content = canonicalController.pageView?.contentFrameForPageSizing(original, sizing: zoomView.effectivePageSizing) ?? original
        let frame = content.intersection(canvas.bounds)
        return frame.isEmpty || frame.isNull ? nil : frame
    }

    private func layoutOriginalImage() {
        let frame = originalFrame()
        let oldSize = imageView.bounds.size
        if imageView.frame != frame { imageView.frame = frame }
        if oldSize != imageView.bounds.size { dictionaryOverlaysDirty = true }
        texture.update(imageSize: imageView.image?.size, in: imageView.bounds, contentMode: imageView.contentMode)
        #if SUMI
        sumiEdgeBackground.frame = view.bounds
        sumiEdgeBackground.layout(imageFrame: frame)
        let visible = frame.intersection(view.bounds)
        if frame.width > 0, frame.height > 0, !visible.isNull, !visible.isEmpty {
            let crop = CGRect(x: (visible.minX - frame.minX) / frame.width,
                              y: (visible.minY - frame.minY) / frame.height,
                              width: visible.width / frame.width, height: visible.height / frame.height)
            sumiEdgeBackground.update(image: imageView.image, crop: crop)
        } else {
            sumiEdgeBackground.update(image: nil)
        }
        #endif
        overlayView.frame = imageView.bounds
        renderDictionaryOverlaysIfNeeded()
    }

    func refreshImage() {
        guard isViewLoaded else { return }
        let canonicalPage = canonicalController.pageView
        let data = canonicalPage?.gifData
        // Static pages retain their original UIImage identity. Animated leaves
        // share the canonical decoder/clock, rather than decoding twice or
        // restarting either half when recognition finishes.
        if data == nil || data != referenceGIFData {
            if imageView.image !== canonicalPage?.imageView.image {
                #if SUMI
                let firstImage = imageView.image == nil && canonicalPage?.imageView.image != nil
                #endif
                imageView.image = canonicalPage?.imageView.image
                #if SUMI
                if imageView.image == nil {
                    sumiEdgeBackground.update(image: nil)
                    sumiLoadingView.show()
                    imageView.alpha = 1
                } else {
                    var visible = view.window != nil
                    var ancestor: UIView? = view
                    while let candidate = ancestor {
                        if candidate.isHidden || candidate.alpha < 0.01 { visible = false; break }
                        ancestor = candidate.superview
                    }
                    sumiLoadingView.reveal(imageView, animated: firstImage && visible)
                }
                #endif
                view.setNeedsLayout()
            }
        }
        referenceGIFData = data
        if data != nil {
            imageView.animator = canonicalPage?.imageView.animator
        } else {
            // Detach without prepareForReuse: the animator belongs to the
            // canonical page and can still be used by the other visible half.
            imageView.animator = nil
        }
        updateGIFMirroring()
        view.setNeedsLayout()
        zoomView.zoomEnabled = imageView.image != nil
        updateDoubleTapSetting()
        if #available(iOS 16.0, *) {
            let analysis = canonicalController.pageView?.imageAnalaysisInteraction?.analysis
            if liveTextInteraction?.analysis !== analysis { liveTextInteraction?.analysis = analysis }
            liveTextInteraction?.isSupplementaryInterfaceHidden = !shouldShowLiveTextButton
        }
        refreshDictionaryOverlays()
    }

    func refreshDictionaryOverlays() {
        dictionaryOverlaysDirty = true
        renderDictionaryOverlaysIfNeeded()
    }

    private func renderDictionaryOverlaysIfNeeded() {
        #if SUMI
        overlays.clear()
        return
        #else
        guard isViewLoaded, dictionaryOverlaysDirty else { return }
        guard imageView.image == nil || imageView.bounds.width > 0 && imageView.bounds.height > 0 else { return }
        dictionaryOverlaysDirty = false
        overlays.clear()
        guard #available(iOS 18.0, *), AppSettings.dictionary.enable.get(), AppSettings.dictionary.textOverlayMode.get(),
              let recognizer = canonicalController.pageView?.textRecognizer, let image = imageView.image,
              imageView.bounds.width > 0, imageView.bounds.height > 0 else { return }
        overlays.render(overlays: recognizer.paragraphOverlays(in: imageView, imageSize: image.size))
        #endif
    }

    func dismissActiveDictionaryOverlay() -> Bool { overlays.dismissActive() }

    private func updateDoubleTapSetting() {
        zoomView.doubleTapEnabled = !AppSettings.dictionary.isReaderDoubleTapDisabled(language: canonicalController.page?.language)
    }

    func setLiveTextHidden(_ hidden: Bool) {
        shouldShowLiveTextButton = !hidden
        if #available(iOS 16.0, *), liveTextInteraction?.selectableItemsHighlighted == false {
            liveTextInteraction?.isSupplementaryInterfaceHidden = hidden
        }
    }

    func clearLiveTextSelection() {
        if #available(iOS 16.0, *), let interaction = liveTextInteraction {
            interaction.resetTextSelection()
            let analysis = interaction.analysis
            interaction.analysis = nil
            interaction.analysis = analysis
            interaction.isSupplementaryInterfaceHidden = !shouldShowLiveTextButton
        }
    }
}

/// Gifu's Animator has one delegate. Its public activeFrame can nevertheless be
/// shared by multiple GIFImageViews. Invalidate visible leaf layers together on
/// display ticks; both then read the same frame at the Core Animation commit.
/// This never reruns OCR or changes the canonical bitmap/content callbacks.
@MainActor
private final class ReaderBookGIFFrameMirror: NSObject {
    private weak var imageView: GIFImageView?
    private var displayLink: CADisplayLink?

    init(imageView: GIFImageView) {
        self.imageView = imageView
        super.init()
    }

    func start() {
        guard displayLink == nil, let imageView, imageView.window != nil, imageView.isAnimatingGIF else { return }
        let link = CADisplayLink(target: self, selector: #selector(updateFrame))
        displayLink = link
        link.add(to: .main, forMode: .common)
        updateFrame()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateFrame() {
        guard let imageView, imageView.window != nil, imageView.isAnimatingGIF else {
            stop()
            return
        }
        if let frame = imageView.activeFrame, imageView.image !== frame {
            imageView.layer.setNeedsDisplay()
        }
    }
}
