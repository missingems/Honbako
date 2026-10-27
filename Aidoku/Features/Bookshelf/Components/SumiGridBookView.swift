#if SUMI
import Nuke
import SwiftUI
import UIKit

/// The original cover print, shared unchanged with pickup and return animations.
final class SumiGridBookView: UIImageView, SumiGridBookArtworkProviding {
    private(set) var coverArtwork: UIImage?
    private(set) var bookPose = SumiGridBookPose(seed: 0)
    var renderedBookPose: SumiGridBookPose? { nil }
    private var identity: String?
    private var representedBookID: String?
    private var isBookTransitionActive = false
    private var holdsVisibleEdition = false
    private var refreshOnNextAttachment = false
    private var pendingArtwork: (cover: UIImage, rendered: UIImage, physical: Bool)?
    private var pendingBook: SumiBook?
    private var coverTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .scaleAspectFill
        clipsToBounds = true
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        accessibilityIdentifier = "Sumi.Grid.Cover"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { coverTask?.cancel() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    func beginBookTransition() {
        layer.removeAnimation(forKey: "Sumi.CoverLoaded")
        isBookTransitionActive = true
        holdsVisibleEdition = true
        refreshOnNextAttachment = false
    }

    func endBookTransition() {
        isBookTransitionActive = false
        // Keep the exact returned edition. A cover that finished loading while
        // reading may replace it only after this tile leaves and returns.
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            if !isBookTransitionActive { refreshOnNextAttachment = true }
            return
        }
        guard refreshOnNextAttachment, !isBookTransitionActive else {
            refreshOnNextAttachment = false
            return
        }
        refreshOnNextAttachment = false
        holdsVisibleEdition = false
        if let pendingArtwork {
            self.pendingArtwork = nil
            if pendingArtwork.physical {
                applyRenderedEdition(cover: pendingArtwork.cover, rendered: pendingArtwork.rendered)
            } else {
                applyFlatEdition(cover: pendingArtwork.cover)
            }
        }
        if let pendingBook {
            self.pendingBook = nil
            configure(book: pendingBook)
        }
    }

    /// Loading new artwork never changes the edition already lifted from the grid.
    func applyFlatEdition(cover: UIImage, animated: Bool = false) {
        if holdsVisibleEdition {
            pendingArtwork = (cover, cover, false)
        } else {
            coverArtwork = cover
            if animated, image !== cover, window != nil, !UIAccessibility.isReduceMotionEnabled {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.2
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(fade, forKey: "Sumi.CoverLoaded")
            }
            image = cover
        }
    }

    /// Kept for callers returning an older cached edition. Covers always show
    /// their original unlit print now.
    func applyRenderedEdition(cover: UIImage, rendered _: UIImage) {
        applyFlatEdition(cover: cover)
    }

    func configure(book: SumiBook) {
        let requestedIdentity = "\(book.presentation.id)|\(book.coverURL?.absoluteString ?? "placeholder")"
        guard identity != requestedIdentity else { return }
        if holdsVisibleEdition, representedBookID == book.presentation.id {
            pendingBook = book
            return
        }
        if representedBookID != book.presentation.id {
            layer.removeAnimation(forKey: "Sumi.CoverLoaded")
            image = nil
            coverArtwork = nil
            pendingArtwork = nil
            pendingBook = nil
            holdsVisibleEdition = false
        }
        representedBookID = book.presentation.id
        identity = requestedIdentity
        bookPose = SumiGridBookPose(seed: book.presentation.placementSeed)
        coverTask?.cancel()
        let fallback = ImageRenderer(content: BookPrintedFrontCover(book: book.presentation)
            .frame(width: 340, height: 500))
        fallback.scale = 1
        let placeholder = fallback.uiImage
        if let placeholder { applyFlatEdition(cover: placeholder) }
        coverTask = Task { @MainActor [weak self] in
            let loaded = await Self.loadCover(for: book)
            guard !Task.isCancelled, self?.identity == requestedIdentity else { return }
            if let loaded { self?.applyFlatEdition(cover: loaded, animated: true) }
        }

    }
    private static func loadCover(for book: SumiBook) async -> UIImage? {
        guard let url = book.coverURL else { return nil }
        let source = await SourceManager.shared.source(for: book.sourceKey)
        guard !Task.isCancelled else { return nil }
        let request: URLRequest
        if let local = url.toAidokuFileUrl() { request = URLRequest(url: local) }
        else if let source { request = await source.getModifiedImageRequest(url: url, context: nil) }
        else { request = URLRequest(url: url) }
        var processors: [ImageProcessing] = [DownsampleProcessor(width: 640)]
        if let source, source.features.processesCovers { processors.append(CoverInterceptorProcessor(source: source)) }
        let imageRequest = ImageRequest(urlRequest: request, processors: processors,
                                       userInfo: [.processesKey: source?.features.processesCovers ?? false])
        return try? await ImagePipeline.shared.image(for: imageRequest)
    }

}
#endif
