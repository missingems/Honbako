//
//  ReaderPageViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import AidokuRunner
import UIKit

class ReaderPageViewController: BaseObservingViewController {
    enum InfoPageType {
        case previous
        case next
    }

    enum PageType {
        case info(InfoPageType)
        case page
    }

    let type: PageType

    weak var delegate: ReaderHoldingDelegate?

    private var infoView: ReaderInfoPageView?
    private(set) var zoomView: ZoomableScrollView?
    private(set) var pageView: ReaderPageView?
    #if SUMI
    var sumiPageSizing: ReaderPageSizing? = .fit {
        didSet { zoomView?.pageSizingOverride = sumiPageSizing }
    }
    var bookBindingEdge: ReaderBookSpineView.BindingEdge = .none {
        didSet { if isViewLoaded { updatePaperShape() } }
    }
    private let paperMask = CAShapeLayer()
    var sumiContinueChapter: (() -> Void)? {
        didSet { infoView?.sumiContinue = sumiContinueChapter }
    }
    #endif

    private lazy var reloadButton = {
        let reloadButton = UIButton(type: .roundedRect)
        reloadButton.isHidden = true
        reloadButton.setTitle(NSLocalizedString("RELOAD"), for: .normal)
        reloadButton.addTarget(self, action: #selector(reload), for: .touchUpInside)
        reloadButton.configuration = .borderless()
        reloadButton.configuration?.contentInsets = .init(top: 15, leading: 15, bottom: 15, trailing: 15)
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        return reloadButton
    }()

    var currentChapter: AidokuRunner.Chapter? {
        get { infoView?.currentChapter }
        set { infoView?.currentChapter = newValue }
    }
    var previousChapter: AidokuRunner.Chapter? {
        get { infoView?.previousChapter }
        set { infoView?.previousChapter = newValue }
    }
    var nextChapter: AidokuRunner.Chapter? {
        get { infoView?.nextChapter }
        set { infoView?.nextChapter = newValue }
    }

    var page: Page?
    private var pageSet = false
    private var didLoadPageSuccessfully = false
    private var sourceId: String?
    private var imageAspectRatio: CGFloat? // Aspect ratio of the image, > 1 means wide image
    private var pageBackground: PageBackground?
    private var backgroundLayoutSize: CGSize = .zero

    // disable auto page background in double page controller
    var isInDoublePageController = false {
        didSet {
            loadPageBackground()
            if isInDoublePageController {
                zoomView?.zoomEnabled = false
            } else {
                zoomView?.zoomEnabled = didLoadPageSuccessfully
                zoomView?.updatePageSizing(resetZoom: true)
            }
        }
    }
    var doublePageRestorationConstraints: [NSLayoutConstraint] = []

    /// Callback when image aspect ratio is updated
    var onAspectRatioUpdated: (() -> Void)?

    /// Callback when image loading is complete and wide image status is determined
    var onImageisWideImage: ((Bool) -> Void)?

    init(
        type: PageType,
        delegate: ReaderHoldingDelegate?,
        temporaryPageStore: ReaderTemporaryPageStore? = nil
    ) {
        self.type = type
        self.delegate = delegate
        super.init()

        // need this so the page / chapters can be set before the rest of the views are loaded
        switch type {
            case .info(let infoPageType):
                infoView = ReaderInfoPageView(type: infoPageType == .previous ? .previous : .next)
            case .page:
                guard let temporaryPageStore else {
                    fatalError("ReaderPageViewController with type page requires a temporary page store")
                }
                pageView = ReaderPageView(parent: self, temporaryPageStore: temporaryPageStore)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func configure() {
        switch type {
            case .info:
                // info view
                guard let infoView else { return }
                infoView.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(infoView)

            case .page:
                // zoom view
                let zoomView = ZoomableScrollView(frame: view.bounds)
                zoomView.zoomEnabled = didLoadPageSuccessfully && !isInDoublePageController
                // A book leaf may be exactly half a point wide on a 3x display.
                // Auto Layout rounds opposite edges to different physical pixels
                // after reparenting, which changes Fill Width's baseline scale.
                zoomView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                self.zoomView = zoomView
                #if SUMI
                zoomView.pageSizingOverride = sumiPageSizing
                #endif
                updateDoubleTapZoomSetting()
                view.addSubview(zoomView)

                // page view
                guard let pageView else { return }
                pageView.translatesAutoresizingMaskIntoConstraints = false
                zoomView.addSubview(pageView)
                zoomView.zoomView = pageView
                zoomView.pageContentFrame = { [weak self] in
                    guard let self, !self.isInDoublePageController,
                          let pageView = self.pageView, let image = pageView.imageView.image else { return nil }
                    let frame = ReaderPageSizingGeometry.aspectFitFrame(imageSize: image.size, in: pageView.imageView.bounds)
                    return pageView.contentFrameForPageSizing(pageView.imageView.convert(frame, to: pageView),
                        sizing: self.zoomView?.effectivePageSizing)
                }
                // hide live text button when zoomed in
                zoomView.onZoomScaleChanged = { [weak self] scale in
                    self?.pageView?.setLiveTextHidden(scale != 1 || (self?.delegate?.barsHidden ?? false))
                    #if SUMI
                    self?.updatePaperShape()
                    #endif
                }
                view.addSubview(reloadButton)
        }
    }

    override func constrain() {
        if let infoView {
            NSLayoutConstraint.activate([
                infoView.topAnchor.constraint(equalTo: view.topAnchor),
                infoView.leftAnchor.constraint(equalTo: view.leftAnchor),
                infoView.rightAnchor.constraint(equalTo: view.rightAnchor),
                infoView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        } else if let zoomView, let pageView {
            // Bars overlay the artwork. A control tap must not change its
            // aspect-fit frame, Fill Width scale, or current reading position.
            NSLayoutConstraint.activate([
                pageView.topAnchor.constraint(equalTo: zoomView.contentLayoutGuide.topAnchor),
                pageView.leadingAnchor.constraint(equalTo: zoomView.contentLayoutGuide.leadingAnchor),
                pageView.trailingAnchor.constraint(equalTo: zoomView.contentLayoutGuide.trailingAnchor),
                pageView.bottomAnchor.constraint(equalTo: zoomView.contentLayoutGuide.bottomAnchor),
                pageView.widthAnchor.constraint(equalTo: zoomView.frameLayoutGuide.widthAnchor),
                pageView.heightAnchor.constraint(equalTo: zoomView.frameLayoutGuide.heightAnchor),

                reloadButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                reloadButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
    }

    override func observe() {
        addObserver(forName: "Reader.backgroundColor") { [weak self] _ in
            self?.loadPageBackground()
        }
        for key in [
            "Reader.disableDoubleTap",
            AppSettings.dictionary.enable.key,
            AppSettings.dictionary.lookupGesture.key,
            AppSettings.dictionary.restrictOCRLanguages.key,
            AppSettings.dictionary.restrictedOCRLanguages.key
        ] {
            addObserver(forName: key) { [weak self] _ in
                self?.updateDoubleTapZoomSetting()
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        loadPageBackground() // fix page background resetting on system appearance change
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The actual page surface now owns its rendering size again, rather
        // than the two clipping leaves used for a full-width wide image.
        pageView?.clearReferenceViewport()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let zoomView {
            if zoomView.frame != view.bounds { zoomView.frame = view.bounds }
            zoomView.layoutIfNeeded()
            zoomView.updatePageSizing()
        }
        #if SUMI
        updatePaperShape()
        #endif
        let size = view.bounds.size
        guard size != backgroundLayoutSize else { return }
        let wasLandscape = backgroundLayoutSize.width > backgroundLayoutSize.height
        backgroundLayoutSize = size
        loadPageBackground(forceReload: wasLandscape != (size.width > size.height))
    }

    #if SUMI
    func updatePaperShape() {
        guard case .page = type else { return }
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

    func setPage(_ page: Page, sourceId: String? = nil, skipProcessing: Bool = false) {
        guard !pageSet, let pageView else { return }
        pageSet = true
        self.page = page
        self.sourceId = sourceId
        updateDoubleTapZoomSetting()
        reloadButton.isHidden = true
        zoomView?.zoomEnabled = false
        Task {
            let result = await pageView.setPage(page, sourceId: sourceId, skipProcessing: skipProcessing)
            guard self.page == page else { return }

            didLoadPageSuccessfully = result
            zoomView?.zoomEnabled = result && !isInDoublePageController
            if !isInDoublePageController {
                view.layoutIfNeeded()
                zoomView?.updatePageSizing(resetZoom: true)
            }
            reloadButton.isHidden = result

            // Update aspect ratio
            let oldAspectRatio = imageAspectRatio
            if result, let image = pageView.imageView.image {
                imageAspectRatio = image.size.width / image.size.height
            } else {
                imageAspectRatio = nil
            }

            // Notify if aspect ratio changed and became wide image
            if oldAspectRatio != imageAspectRatio && isWideImage {
                onAspectRatioUpdated?()
            }

            // Notify when image loading is complete with wide image status
            onImageisWideImage?(isWideImage)

            // determine page background color
            loadPageBackground()
        }
    }

    private func loadPageBackground(forceReload: Bool = false) {
        // ensure no old gradients are left
        view.layer.sublayers?.removeAll(where: { $0 is CAGradientLayer })

        #if SUMI
        view.backgroundColor = SumiPaperSurface.backgroundColor
        return
        #else

        if
            UserDefaults.standard.string(forKey: "Reader.backgroundColor") == "auto",
            !isInDoublePageController,
            pageBackground != nil || pageView?.imageView.image != nil
        {
            let background = if !forceReload, let pageBackground {
                pageBackground
            } else if let image = pageView?.imageView.image {
                PageBackground.choose(for: image, isLandscape: view.bounds.width > view.bounds.height)
            } else {
                PageBackground.color(.clear)
            }
            pageBackground = background
            switch background {
                case .color(let color):
                    view.backgroundColor = color
                case .gradient(let gradient):
                    gradient.frame = view.bounds
                    view.layer.insertSublayer(gradient, at: 0)
            }
        } else {
            view.backgroundColor = nil
        }
        #endif
    }

    @objc func reload() {
        guard let page else { return }
        pageSet = false
        reloadButton.isHidden = true
        pageView?.progressView.setProgress(value: 0, withAnimation: false)
        pageView?.progressView.isHidden = false
        setPage(page, sourceId: sourceId)
    }

    func clearPage() {
        page = nil
        pageSet = false
        pageView?.setPageImage(nil)
        zoomView?.zoomEnabled = false
        imageAspectRatio = nil
    }

    #if SUMI
    func sumiReleasePreloadedImage() {
        guard pageSet else { return }
        page = nil
        pageSet = false
        didLoadPageSuccessfully = false
        pageView?.setPageImage(nil)
        zoomView?.zoomEnabled = false
        // Retain the known aspect ratio so eviction does not regroup a wide
        // source page as two unrelated portrait pages when revisiting it.
    }
    #endif

    /// Check if this is a wide image (aspect ratio > 1)
    var isWideImage: Bool {
        guard let imageAspectRatio else { return false }
        return imageAspectRatio > 1
    }

    private func updateDoubleTapZoomSetting() {
        zoomView?.doubleTapEnabled = !AppSettings.dictionary.isReaderDoubleTapDisabled(language: page?.language)
    }
}
