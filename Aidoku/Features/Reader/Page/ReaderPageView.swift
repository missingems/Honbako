//
//  ReaderPageView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import AidokuRunner
import Gifu
import MarkdownUI
import Nuke
import SwiftUI
import Vision
import VisionKit
import ZIPFoundation

class ReaderPageView: UIView {
    weak var parent: UIViewController?

    private let temporaryPageStore: ReaderTemporaryPageStore

    let imageView = GIFImageView()
    private(set) var gifData: Data?
    private var gifGeneration = 0
    private(set) var verticalContentBounds = ReaderVerticalContentBounds.fullImage
    private var verticalBoundsTask: Task<Void, Never>?
    private var verticalBoundsGeneration = 0
    private var didRequestVerticalBounds = false
    private let paperTextureView = ReaderPaperTextureView()
    let progressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))

    @available(iOS 16.0, *)
    var imageAnalaysisInteraction: ImageAnalysisInteraction? {
        imageView.interactions.first as? ImageAnalysisInteraction
    }

    private var textView: UIHostingController<MarkdownView>?

    private var _textRecognizer: Any?
    @available(iOS 18.0, *)
    var textRecognizer: TextRecognizer? {
        get { _textRecognizer as? TextRecognizer }
        set { _textRecognizer = newValue }
    }

    private var imageWidthConstraint: NSLayoutConstraint?
    private var imageHeightConstraint: NSLayoutConstraint?
    private var imageLayoutSize: CGSize = .zero
    private var renderedImageFrame: CGRect = .zero
    private var schedulesPageSizingUpdate = false
    private var imageTask: ImageTask?
    private var sourceId: String?
    private var shouldShowLiveTextButton = false
    @available(iOS 16.0, *)
    private static let sharedImageAnalyzer = ImageAnalyzer()
    private var liveTextTask: Task<Void, Never>?
    private var liveTextGeneration = 0

    private var needsDictionaryOverlayRender = false
    private var dictionaryAnalysisTask: Task<Void, Never>?
    private let dictionaryOverlayContainerView = DictionaryOverlayPassthroughView()
    private let dictionaryOverlayController = DictionaryOverlayController()
    var onDictionaryOverlayTap: ((String, String, CGRect, [CGRect]) -> Void)? {
        get { dictionaryOverlayController.onLookup }
        set { dictionaryOverlayController.onLookup = newValue }
    }

    private var completion: ((Bool) -> Void)?

    // MARK: - Reload functionality properties
    private var currentPage: Page?
    private var currentImageRequest: ImageRequest?
    private var processedPagePixelWidth: CGFloat?
    private var referenceViewport: (width: CGFloat, scale: CGFloat)?
    private var skipsProcessing = false
    private var isRefreshingResolution = false
    #if SUMI
    private let sumiLoadingView = SumiPageImageLoadingView()
    private let sumiEdgeBackground = SumiPageEdgeBackgroundView()
    private var sumiLoadGeneration = 0
    var sumiIsImageReady: Bool {
        imageView.image != nil && !sumiLoadingView.isRevealing && imageView.alpha > 0.99 && sumiEdgeBackground.isReady
    }

    func sumiRevealAfterLoadingPlaceholder() {
        guard imageView.image != nil else { return }
        sumiLoadingView.reveal(imageView, animated: window != nil) { [weak self] in
            self?.onReferenceContentChanged?()
        }
        onReferenceContentChanged?()
    }

    private var sumiIsVisible: Bool {
        guard window != nil else { return false }
        var ancestor: UIView? = self
        while let view = ancestor {
            if view.isHidden || view.alpha < 0.01 { return false }
            ancestor = view.superview
        }
        return true
    }
    #endif

    /// Live book leaves display this same bitmap through separate clipping
    /// views. Notify them after image or recognition results change.
    var onReferenceContentChanged: (() -> Void)?

    private var pageWidth: CGFloat? {
        [referenceViewport?.width ?? 0, bounds.width, parent?.view.bounds.width ?? 0, window?.bounds.width ?? 0]
            .first { $0 > 0 && $0.isFinite }
    }

    private var pageDisplayScale: CGFloat { max(1, referenceViewport?.scale ?? traitCollection.displayScale) }

    func updateReferenceViewport(width: CGFloat, displayScale: CGFloat) {
        guard width.isFinite, width > 0, displayScale.isFinite, displayScale > 0 else { return }
        if referenceViewport?.width != width || referenceViewport?.scale != displayScale {
            referenceViewport = (width, displayScale)
        }
        // A smaller preload can finish after the proxy first reports its size.
        // Recheck that loaded variant without requiring another geometry change.
        refreshResolutionIfNeeded()
    }

    func clearReferenceViewport() {
        guard referenceViewport != nil else { return }
        referenceViewport = nil
        setNeedsLayout()
    }

    init(temporaryPageStore: ReaderTemporaryPageStore) {
        self.temporaryPageStore = temporaryPageStore
        super.init(frame: .zero)
        configure()
        constrain()
    }

    convenience init(parent: UIViewController?, temporaryPageStore: ReaderTemporaryPageStore) {
        self.init(temporaryPageStore: temporaryPageStore)
        self.parent = parent
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        verticalBoundsTask?.cancel()
        cancelDictionaryTextAnalysis()
    }

    func configure() {
        progressView.trackColor = .quaternaryLabel
        progressView.progressColor = tintColor
        progressView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressView)
        #if SUMI
        sumiEdgeBackground.frame = bounds
        sumiEdgeBackground.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sumiLoadingView.frame = bounds
        sumiLoadingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(sumiLoadingView)
        addSubview(sumiEdgeBackground)
        #endif

        #if !SUMI
        if #available(iOS 16.0, *), UserDefaults.standard.bool(forKey: "Reader.liveText"), ImageAnalyzer.isSupported {
            let interaction = ImageAnalysisInteraction()
            interaction.preferredInteractionTypes = .automatic
            imageView.addInteraction(interaction)
        }
        #endif

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        imageView.addSubview(paperTextureView)

        dictionaryOverlayContainerView.translatesAutoresizingMaskIntoConstraints = false
        dictionaryOverlayContainerView.backgroundColor = .clear
        dictionaryOverlayContainerView.isUserInteractionEnabled = true
        imageView.addSubview(dictionaryOverlayContainerView)
        dictionaryOverlayController.containerView = dictionaryOverlayContainerView

        imageWidthConstraint = imageView.widthAnchor.constraint(equalTo: widthAnchor)
        imageWidthConstraint?.isActive = true
    }

    func constrain() {
        NSLayoutConstraint.activate([
            progressView.widthAnchor.constraint(equalToConstant: progressView.frame.width),
            progressView.heightAnchor.constraint(equalToConstant: progressView.frame.height),
            progressView.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressView.centerYAnchor.constraint(equalTo: centerYAnchor),

            imageView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),

            dictionaryOverlayContainerView.topAnchor.constraint(equalTo: imageView.topAnchor),
            dictionaryOverlayContainerView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            dictionaryOverlayContainerView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            dictionaryOverlayContainerView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if bounds.size != imageLayoutSize {
            imageLayoutSize = bounds.size
            fixImageSize()
        }
        if let image = imageView.image {
            paperTextureView.update(imageSize: image.size, in: imageView.bounds, contentMode: imageView.contentMode)
            let frame = imageView.convert(
                ReaderPageSizingGeometry.aspectFitFrame(imageSize: image.size, in: imageView.bounds), to: self
            )
            #if SUMI
            sumiEdgeBackground.frame = bounds
            sumiEdgeBackground.layout(imageFrame: frame)
            #endif
            if frame != renderedImageFrame {
                renderedImageFrame = frame
                schedulePageSizingUpdate()
            }
        } else {
            paperTextureView.update(imageSize: nil, in: imageView.bounds, contentMode: imageView.contentMode)
            #if SUMI
            sumiEdgeBackground.update(image: nil)
            #endif
        }
        refreshResolutionIfNeeded()

        if needsDictionaryOverlayRender {
            renderDictionaryOverlaysIfNeeded()
        }
    }

    private func schedulePageSizingUpdate() {
        guard !schedulesPageSizingUpdate else { return }
        schedulesPageSizingUpdate = true
        // Image constraints may settle after the scroll view's layout pass.
        // Measure on the next turn, including when this page belongs to a spread.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.schedulesPageSizingUpdate = false
            var ancestor = self.superview
            while let view = ancestor {
                if let scrollView = view as? ZoomableScrollView {
                    scrollView.updatePageSizing()
                    return
                }
                ancestor = view.superview
            }
        }
    }
}

extension ReaderPageView {
    private func refreshResolutionIfNeeded() {
        guard
            !isRefreshingResolution, !skipsProcessing,
            UserDefaults.standard.bool(forKey: "Reader.downsampleImages"),
            imageView.image != nil, imageTask == nil,
            let currentPage, let processedPagePixelWidth, let pageWidth,
            pageWidth * pageDisplayScale > processedPagePixelWidth + 1
        else { return }

        isRefreshingResolution = true
        Task { [weak self] in
            guard let self else { return }
            // Keep the existing image visible while the larger variant loads.
            _ = await setPage(currentPage, sourceId: sourceId)
            isRefreshingResolution = false
            setNeedsLayout()
        }
    }

    func setPage(_ page: Page, sourceId: String? = nil, skipProcessing: Bool = false) async -> Bool {
        // Store current page data for reload functionality
        self.currentPage = page
        skipsProcessing = skipProcessing
        processedPagePixelWidth = !skipProcessing && UserDefaults.standard.bool(forKey: "Reader.downsampleImages")
            ? pageWidth.map { $0 * pageDisplayScale } : nil

        if sourceId != nil {
            self.sourceId = sourceId
        }
        cancelLiveTextAnalysis()

        if var image = page.image {
            if !skipProcessing {
                if UserDefaults.standard.bool(forKey: "Reader.cropBorders") {
                    image = CropBordersProcessor().process(image) ?? image
                }
                if UserDefaults.standard.bool(forKey: "Reader.downsampleImages") {
                    if let pageWidth {
                        image = DownsampleProcessor(width: pageWidth, scaleFactor: pageDisplayScale).process(image) ?? image
                    }
                } else if UserDefaults.standard.bool(forKey: "Reader.upscaleImages") {
                    image = UpscaleProcessor().process(image) ?? image
                }
            }
            setPageImage(image)
            return true
        } else if let zipURL = page.zipURL, let url = URL(string: zipURL), let filePath = page.imageURL {
            return await setPageImage(zipURL: url, filePath: filePath)
        } else if let urlString = page.imageURL, let url = URL(string: urlString) {
            return await setPageImage(url: url, context: page.context, sourceId: self.sourceId)
        } else if let base64 = page.base64 {
            return await setPageImage(base64: base64, key: page.hashValue)
        } else if let text = page.text {
            setPageText(text: text)
            return true
        } else {
            return false
        }
    }

    /// Creates the image request used to fetch a page image.
    static func imageRequest(
        url: URL,
        context: PageContext? = nil,
        sourceKey: String? = nil,
        downsampleWidth: CGFloat? = nil,
        displayScale: CGFloat? = nil
    ) async -> ImageRequest {
        let source: AidokuRunner.Source? = if let sourceKey {
            await SourceManager.shared.source(for: sourceKey)
        } else {
            nil
        }
        return await imageRequest(
            url: url,
            context: context,
            source: source,
            downsampleWidth: downsampleWidth,
            displayScale: displayScale
        )
    }

    static func imageRequest(
        url: URL,
        context: PageContext? = nil,
        source: AidokuRunner.Source?,
        downsampleWidth: CGFloat? = nil,
        displayScale: CGFloat? = nil
    ) async -> ImageRequest {
        let urlRequest = if !url.isFileURL, let source {
            await source.getModifiedImageRequest(url: url, context: context)
        } else {
            URLRequest(url: url)
        }

        var processors: [ImageProcessing] = []
        var usePageProcessor = false
        if let source {
            // only process pages if the source supports it and the image isn't downloaded
            // note: also skips processing raw data pages (assuming final data is already provided and doesn't need to be modified)
            //       this should probably be changed in the future to be more correct though
            if source.features.processesPages, !url.isFileURL {
                processors.append(PageInterceptorProcessor(source: source, pageContext: context))
                usePageProcessor = true
            }
        }
        if UserDefaults.standard.bool(forKey: "Reader.cropBorders") {
            processors.append(CropBordersProcessor())
        }
        if UserDefaults.standard.bool(forKey: "Reader.downsampleImages") {
            if let downsampleWidth, downsampleWidth > 0 {
                processors.append(DownsampleProcessor(width: downsampleWidth, scaleFactor: displayScale))
            }
        } else if UserDefaults.standard.bool(forKey: "Reader.upscaleImages") {
            processors.append(UpscaleProcessor())
        }

        #if SUMI
        processors.append(SumiPageEdgePreparationProcessor(request: urlRequest, sourceKey: source?.key,
            sourceVersion: source?.version, pageContext: context, processors: processors))
        #endif
        return ImageRequest(
            urlRequest: urlRequest,
            processors: processors,
            userInfo: [.processesKey: usePageProcessor]
        )
    }

    func setPageImage(url: URL, context: PageContext? = nil, sourceId: String? = nil) async -> Bool {
        #if SUMI
        let generation = sumiLoadGeneration
        #endif
        // remove text view if it exists
        if let textView {
            textView.view.removeFromSuperview()
            textView.didMove(toParent: nil)
            self.textView = nil
        }

        let request: ImageRequest

        if let imageTask {
            switch imageTask.state {
                case .running:
                    if completion != nil {
                        completion!(imageView.image != nil)
                    }
                    return await withCheckedContinuation({ continuation in
                        self.completion = { success in
                            self.completion = nil
                            continuation.resume(returning: success)
                        }
                    })
                case .completed:
                    if imageView.image == nil {
                        request = imageTask.request
                    } else {
                        return true
                    }
                case .cancelled:
                    request = imageTask.request
            }
        } else {
            request = await Self.imageRequest(
                url: url,
                context: context,
                sourceKey: sourceId,
                downsampleWidth: pageWidth,
                displayScale: pageDisplayScale
            )
        }

        // Store current image request for reload functionality
        #if SUMI
        guard generation == sumiLoadGeneration else { return false }
        #endif
        self.currentImageRequest = request

        if imageView.image == nil {
            progressView.setProgress(value: 0, withAnimation: false)
            progressView.isHidden = false
        }

        return await startImageTask(request)
    }

    private func startImageTask(_ request: ImageRequest) async -> Bool {
        #if SUMI
        let generation = sumiLoadGeneration
        #endif
        imageTask = ImagePipeline.shared.loadImage(
            with: request,
            progress: { [weak self] _, completed, total in
                guard let self else { return }
                self.progressView.setProgress(value: Float(completed) / Float(total), withAnimation: false)
            },
            completion: { _ in }
        )
        // hide progress view when task completes
        defer {
            #if SUMI
            if generation == sumiLoadGeneration {
                progressView.isHidden = true
                imageTask = nil
            }
            #else
            progressView.isHidden = true
            imageTask = nil
            #endif
        }
        do {
            let response = try await imageTask?.response
            guard let response else {
                return false
            }
            #if SUMI
            guard generation == sumiLoadGeneration, !Task.isCancelled else { return false }
            #endif
            setPageImage(response.image, gifData: response.container.type == .gif ? response.container.data : nil)
            completion?(true)
            return true
        } catch {
            #if SUMI
            guard generation == sumiLoadGeneration, !Task.isCancelled else { return false }
            #endif
            // we can still send to image processor even if the request failed
            if request.userInfo[.processesKey] as? Bool == true {
                let processor = request.processors.first(where: { $0 is PageInterceptorProcessor }) as? PageInterceptorProcessor
                if let processor {
                    let result: Nuke.ImageContainer?
                    switch error {
                        case .dataLoadingFailed, .dataIsEmpty, .decodingFailed:
                            result = await Task.detached {
                                try? processor.processWithoutImage(request: request)
                            }.value
                        default:
                            result = nil
                    }
                    if let result {
                        #if SUMI
                        guard generation == sumiLoadGeneration, !Task.isCancelled else { return false }
                        #endif
                        setPageImage(result.image, gifData: result.type == .gif ? result.data : nil)
                        completion?(true)
                        return true
                    }
                }
            }
            completion?(false)
            return false
        }
    }

    func setPageImage(base64: String, key: Int) async -> Bool {
        #if SUMI
        let generation = sumiLoadGeneration
        #endif
        // remove text view if it exists
        if let textView {
            textView.view.removeFromSuperview()
            textView.didMove(toParent: nil)
            self.textView = nil
        }

        let downsampleProcessor: DownsampleProcessor? = if UserDefaults.standard.bool(forKey: "Reader.downsampleImages"), let pageWidth {
            DownsampleProcessor(width: pageWidth, scaleFactor: pageDisplayScale)
        } else {
            nil
        }
        let fullKey = "\(key)-\(ImageProcessingSettingsKey.getProcessorSettingsKey())-\(downsampleProcessor?.identifier ?? "original")"
        let request = ImageRequest(id: fullKey, data: { Data() })

        // Store current image request for reload functionality
        self.currentImageRequest = request

        progressView.setProgress(value: 0, withAnimation: false)
        progressView.isHidden = false
        defer { progressView.isHidden = true }

        if ImagePipeline.shared.cache.containsCachedImage(for: request) {
            let imageContainer = ImagePipeline.shared.cache.cachedImage(for: request)
            setPageImage(imageContainer?.image)
            return true
        }

        let image: UIImage? = await Task.detached {
            guard
                let imageData = Data(base64Encoded: base64),
                var image = UIImage(data: imageData)
            else {
                return nil
            }

            if UserDefaults.standard.bool(forKey: "Reader.cropBorders") {
                let processor = CropBordersProcessor()
                if let processedImage = processor.process(image) {
                    image = processedImage
                }
            }
            if let processor = downsampleProcessor {
                if let processedImage = processor.process(image) {
                    image = processedImage
                }
            } else if !UserDefaults.standard.bool(forKey: "Reader.downsampleImages"), UserDefaults.standard.bool(forKey: "Reader.upscaleImages") {
                let processor = UpscaleProcessor()
                if let processedImage = processor.process(image) {
                    image = processedImage
                }
            }

            #if SUMI
            _ = SumiPreparedPageEdges.prepare(image: image)
            #endif
            return image
        }.value
        #if SUMI
        guard generation == sumiLoadGeneration, !Task.isCancelled else { return false }
        #endif
        guard let image else { return false }

        ImagePipeline.shared.cache.storeCachedImage(ImageContainer(image: image), for: request)
        setPageImage(image)

        return true
    }

    func setPageImage(zipURL: URL, filePath: String) async -> Bool {
        #if SUMI
        let generation = sumiLoadGeneration
        #endif
        guard let extractedURL = await temporaryPageStore.storeArchiveEntry(
            from: zipURL,
            path: filePath
        ) else {
            return false
        }
        #if SUMI
        guard generation == sumiLoadGeneration, !Task.isCancelled else { return false }
        #endif

        if filePath.lowercased().hasSuffix(".txt") {
            guard
                let data = try? Data(contentsOf: extractedURL),
                let text = String(data: data, encoding: .utf8)
            else {
                return false
            }
            setPageText(text: text)
            return true
        }

        // remove text view if it exists
        if let textView {
            textView.view.removeFromSuperview()
            textView.didMove(toParent: nil)
            self.textView = nil
        }

        return await setPageImage(url: extractedURL)
    }

    // match image constraints with image size
    func fixImageSize() {
        guard imageView.image != nil, imageView.image!.size.width > 0 else { return }

        imageHeightConstraint?.isActive = false
        imageWidthConstraint?.isActive = false

        if
            case let height = imageView.image!.size.height * (bounds.width / imageView.image!.size.width),
            height > bounds.height || (parent as? ReaderPageViewController)?.isInDoublePageController == true
        {
            // max height, variable width
            let multiplier = imageView.image!.size.width / imageView.image!.size.height
            imageWidthConstraint = imageView.widthAnchor.constraint(
                equalTo: imageView.heightAnchor,
                multiplier: multiplier
            )
            imageHeightConstraint = imageView.heightAnchor.constraint(equalTo: heightAnchor)
        } else {
            // max width, variable height
            let multiplier = imageView.image!.size.height / imageView.image!.size.width
            imageWidthConstraint = imageView.widthAnchor.constraint(equalTo: widthAnchor)
            imageHeightConstraint = imageView.heightAnchor.constraint(
                equalTo: imageView.widthAnchor,
                multiplier: multiplier
            )
        }
        imageWidthConstraint?.isActive = true
        imageHeightConstraint?.isActive = true
    }

    func setPageText(text: String) {
        resetVerticalContentBounds()
        stopGIFAnimation()
        cancelDictionaryTextAnalysis()
        clearDictionaryOverlays()
        imageView.image = nil
        #if SUMI
        sumiEdgeBackground.update(image: nil)
        #endif
        paperTextureView.update(imageSize: nil, in: imageView.bounds, contentMode: imageView.contentMode)
        onReferenceContentChanged?()
        progressView.isHidden = true

        let view = MarkdownView(text)

        if let textView {
            textView.rootView = view
        } else {
            textView = UIHostingController(rootView: view)
            guard let textView else { return }
            if #available(iOS 16.0, *) {
                textView.sizingOptions = .intrinsicContentSize
            }
            if #available(iOS 16.4, *) {
                // fixes text being shifted when navbar is hidden/shown
                textView.safeAreaRegions = []
            }
            textView.view.translatesAutoresizingMaskIntoConstraints = false
            if let parent {
                parent.addChild(textView)
                textView.didMove(toParent: parent)
            }
            addSubview(textView.view)

            NSLayoutConstraint.activate([
                textView.view.topAnchor.constraint(equalTo: topAnchor),
                textView.view.leadingAnchor.constraint(equalTo: leadingAnchor),
                textView.view.trailingAnchor.constraint(equalTo: trailingAnchor),
                // if the text string is too long, it'll just extend downwards out of bounds
                // we should probably make it scrollable as long as it doesn't mess with the existing swipe gesture
                textView.view.heightAnchor.constraint(greaterThanOrEqualTo: heightAnchor)
            ])
        }
    }

    /// Fill Width changes scroll start/end only. Keeping the image's actual
    /// frame intact preserves source identity, Live Text and dictionary geometry.
    func contentFrameForPageSizing(_ originalFrame: CGRect, sizing: ReaderPageSizing? = nil) -> CGRect {
        let resolvedSizing = sizing ?? AppSettings.reader.pageSizing.get()
        guard resolvedSizing == .fill else { return originalFrame }
        requestVerticalContentBoundsIfNeeded(sizing: resolvedSizing)
        return verticalContentBounds.frame(in: originalFrame)
    }

    private func resetVerticalContentBounds() {
        verticalBoundsTask?.cancel()
        verticalBoundsTask = nil
        verticalBoundsGeneration += 1
        didRequestVerticalBounds = false
        verticalContentBounds = .fullImage
    }

    private func requestVerticalContentBoundsIfNeeded(sizing: ReaderPageSizing? = nil) {
        guard !didRequestVerticalBounds, (sizing ?? AppSettings.reader.pageSizing.get()) == .fill,
              gifData == nil, let image = imageView.image, image.images == nil,
              image.imageOrientation == .up, let cgImage = image.cgImage else { return }
        didRequestVerticalBounds = true
        let generation = verticalBoundsGeneration
        verticalBoundsTask = Task { [weak self] in
            let detector = Task.detached(priority: .utility) {
                ReaderVerticalContentBounds.detect(in: cgImage)
            }
            let result = await withTaskCancellationHandler {
                await detector.value
            } onCancel: {
                detector.cancel()
            }
            guard let self, !Task.isCancelled, self.verticalBoundsGeneration == generation else { return }
            self.verticalBoundsTask = nil
            guard result != self.verticalContentBounds else { return }
            self.verticalContentBounds = result
            self.schedulePageSizingUpdate()
            self.onReferenceContentChanged?()
        }
    }

    private func stopGIFAnimation() {
        gifGeneration += 1
        guard gifData != nil else { return }
        imageView.prepareForReuse()
        gifData = nil
    }

    func setPageImage(_ image: UIImage?, gifData: Data? = nil) {
        #if SUMI
        let firstImage = imageView.image == nil && image != nil
        if image == nil {
            sumiLoadGeneration += 1
            imageTask?.cancel()
            imageTask = nil
            completion?(false)
            completion = nil
            sumiLoadingView.show()
            imageView.alpha = 1
        }
        #endif
        resetVerticalContentBounds()
        cancelLiveTextAnalysis()
        stopGIFAnimation()
        self.gifData = image != nil ? gifData : nil
        imageView.image = image
        #if SUMI
        sumiEdgeBackground.update(image: image)
        if image != nil {
            sumiLoadingView.reveal(imageView, animated: firstImage && sumiIsVisible) { [weak self] in
                self?.onReferenceContentChanged?()
            }
        }
        #endif
        requestVerticalContentBoundsIfNeeded()
        paperTextureView.update(imageSize: image?.size, in: imageView.bounds, contentMode: imageView.contentMode)
        if let data = self.gifData {
            let generation = gifGeneration
            imageView.animate(withGIFData: data, preparationBlock: { [weak self] in
                // Gifu decodes on a background queue. Notify already-visible
                // leaves once frames are ready, never once per animation frame.
                Task { @MainActor [weak self] in
                    guard let self, self.gifGeneration == generation, self.gifData != nil else { return }
                    self.imageView.startAnimatingGIF()
                    self.onReferenceContentChanged?()
                }
            })
        }
        fixImageSize()
        startLiveTextAnalysis()
        scheduleDictionaryTextAnalysis()
        onReferenceContentChanged?()
    }
}

extension ReaderPageView {
    func clearLiveTextSelection() {
        if #available(iOS 16.0, *) {
            guard let interaction = imageAnalaysisInteraction else { return }
            interaction.resetTextSelection()
            guard let analysis = interaction.analysis else { return }
            interaction.analysis = nil
            interaction.analysis = analysis
            interaction.isSupplementaryInterfaceHidden = !shouldShowLiveTextButton
        }
    }

    private func scheduleDictionaryTextAnalysis() {
        #if SUMI
        return
        #else
        needsDictionaryOverlayRender = false
        clearDictionaryOverlays()

        if #available(iOS 18.0, *) {
            DictionaryTextAnalysisScheduler.schedule(
                task: &dictionaryAnalysisTask,
                recognizer: &textRecognizer,
                image: imageView.image,
                language: currentPage?.language
            ) { [weak self] in
                self?.renderDictionaryOverlaysIfNeeded()
                self?.onReferenceContentChanged?()
            }
        }
        #endif
    }

    private func cancelDictionaryTextAnalysis() {
        if #available(iOS 18.0, *) {
            DictionaryTextAnalysisScheduler.cancel(
                task: &dictionaryAnalysisTask,
                recognizer: textRecognizer
            )
        }
    }

    func setLiveTextHidden(_ hidden: Bool) {
        if #available(iOS 16.0, *) {
            shouldShowLiveTextButton = !hidden
            // don't hide if the text highlighting is active
            guard imageAnalaysisInteraction?.selectableItemsHighlighted == false else { return }
            imageAnalaysisInteraction?.isSupplementaryInterfaceHidden = hidden
        }
    }

    // use Task to run LiveText analysis to prevent wide image jumps
    private func startLiveTextAnalysis() {
        guard
            #available(iOS 16.0, *),
            imageAnalaysisInteraction != nil,
            let image = imageView.image,
            (image.cgImage?.height ?? Int(image.size.height * image.scale)) <= 8192
        else {
            return
        }
        liveTextGeneration += 1
        let generation = liveTextGeneration
        liveTextTask?.cancel()
        liveTextTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let analysis = try? await Self.sharedImageAnalyzer.analyze(image, configuration: .init([.text, .machineReadableCode]))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, generation == self.liveTextGeneration else { return }
                self.imageAnalaysisInteraction?.analysis = analysis
                if analysis != nil {
                    self.imageAnalaysisInteraction?.isSupplementaryInterfaceHidden = !self.shouldShowLiveTextButton
                }
                self.onReferenceContentChanged?()
            }
        }
    }

    private func cancelLiveTextAnalysis() {
        liveTextGeneration += 1
        liveTextTask?.cancel()
        liveTextTask = nil
        guard #available(iOS 16.0, *) else { return }
        imageAnalaysisInteraction?.analysis = nil
    }
}

// MARK: - Dictionary Overlay
extension ReaderPageView {
    private func clearDictionaryOverlays() {
        dictionaryOverlayController.clear()
    }

    private func renderDictionaryOverlaysIfNeeded() {
        guard imageView.bounds.width > 0 else {
            needsDictionaryOverlayRender = true
            return
        }

        needsDictionaryOverlayRender = false
        clearDictionaryOverlays()

        guard
            #available(iOS 18.0, *),
            AppSettings.dictionary.enable.get(),
            AppSettings.dictionary.textOverlayMode.get(),
            let textRecognizer,
            let image = imageView.image
        else {
            return
        }

        let overlays = textRecognizer.paragraphOverlays(in: imageView, imageSize: image.size)
        dictionaryOverlayController.render(overlays: overlays)
    }

    func dismissActiveDictionaryOverlay() -> Bool {
        dictionaryOverlayController.dismissActive()
    }

    func setDictionaryOverlayInteractionMode(_ mode: DictionaryOverlayInteractionMode) {
        dictionaryOverlayController.interactionMode = mode
    }
}

// MARK: - Image Reload Functionality
extension ReaderPageView {
    /// Reloads the current image by clearing its cache and re-fetching from the source
    func reloadCurrentImage() async -> Bool {
        guard let currentPage else {
            return false
        }

        // Clear the cache for the current image
        clearCurrentImageCache()

        // Clear the current image to show loading state
        #if SUMI
        setPageImage(nil)
        #else
        resetVerticalContentBounds()
        stopGIFAnimation()
        imageView.image = nil
        onReferenceContentChanged?()
        #endif

        // Reload the image using the original page data
        return await setPage(currentPage, sourceId: sourceId)
    }

    /// Clears the cache entry for the current image
    private func clearCurrentImageCache() {
        guard let currentPage else { return }

        let settingsKey = ImageProcessingSettingsKey.getProcessorSettingsKey()
        // Handle different image types
        if currentPage.imageURL != nil {
            // For URL-based images, use the stored request if available
            if let currentImageRequest {
                ImagePipeline.shared.cache.removeCachedImage(for: currentImageRequest)
            }
        }
        if currentPage.base64 != nil {
            if let currentImageRequest {
                ImagePipeline.shared.cache.removeCachedImage(for: currentImageRequest)
            }
        }
        if let zipURL = currentPage.zipURL, let url = URL(string: zipURL), let filePath = currentPage.imageURL {
            // For zip file images
            var hasher = Hasher()
            hasher.combine(url)
            hasher.combine(filePath)
            let key = String(hasher.finalize())
            let fullKey = "\(key)-\(settingsKey)"
            let request = ImageRequest(id: fullKey, data: { Data() })
            ImagePipeline.shared.cache.removeCachedImage(for: request)
        }
    }

    /// Splits the current image into left and right halves
    func splitImage() -> (left: UIImage, right: UIImage)? {
        guard let image = imageView.image, let cgImage = image.cgImage else { return nil }
        let splitX = CGFloat(cgImage.width) / 2
        let height = CGFloat(cgImage.height)
        guard
            let leftCGImage = cgImage.cropping(
                to: CGRect(x: 0, y: 0, width: splitX, height: height)
            ),
            let rightCGImage = cgImage.cropping(
                to: CGRect(x: splitX, y: 0, width: splitX, height: height)
            )
        else { return nil }

        return (
            UIImage(cgImage: leftCGImage, scale: image.scale, orientation: image.imageOrientation),
            UIImage(cgImage: rightCGImage, scale: image.scale, orientation: image.imageOrientation)
        )
    }
}
