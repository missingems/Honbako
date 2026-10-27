#if SUMI
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
    private var placeholderBook: BookPresentation?
    private var placeholderSize: CGSize = .zero
    private var placeholderScale: CGFloat = 0
    private var placeholderDynamicType: DynamicTypeSize = .large
    private var placeholderColorScheme: ColorScheme = .light

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

    override func layoutSubviews() {
        super.layoutSubviews()
        if !holdsVisibleEdition, !isBookTransitionActive { renderPlaceholder() }
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
            configure(book: pendingBook, dynamicTypeSize: placeholderDynamicType, colorScheme: placeholderColorScheme)
        }
        setNeedsLayout()
    }

    /// Loading new artwork never changes the edition already lifted from the grid.
    func applyFlatEdition(cover: UIImage, animated: Bool = false) {
        placeholderBook = nil
        placeholderSize = .zero
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

    func configure(book: SumiBook, dynamicTypeSize: DynamicTypeSize = .large, colorScheme: ColorScheme? = nil) {
        let appearance = colorScheme ?? (traitCollection.userInterfaceStyle == .dark ? .dark : .light)
        if placeholderDynamicType != dynamicTypeSize || placeholderColorScheme != appearance {
            placeholderDynamicType = dynamicTypeSize
            placeholderColorScheme = appearance
            placeholderSize = .zero
            setNeedsLayout()
        }
        let requestedIdentity = "\(book.presentation.id)|\(book.coverURL?.absoluteString ?? "placeholder")|\(book.title)"
        guard identity != requestedIdentity else {
            // A later coherent refresh can replace a prepared placeholder with
            // warmed artwork without starting a new per-tile image request.
            if !holdsVisibleEdition, let cached = SumiCoverArtworkLoader.shared.cachedCover(for: book),
               coverArtwork !== cached { applyFlatEdition(cover: cached) }
            return
        }
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
        if let cached = SumiCoverArtworkLoader.shared.cachedCover(for: book) {
            applyFlatEdition(cover: cached)
            return
        }
        placeholderBook = book.presentation
        placeholderSize = .zero
        renderPlaceholder()
        guard !SumiCoverArtworkLoader.shared.usesPreparedPlaceholder(for: book) else { return }
        coverTask = Task { @MainActor [weak self] in
            let loaded = await SumiCoverArtworkLoader.shared.loadCover(for: book)
            guard !Task.isCancelled, self?.identity == requestedIdentity else { return }
            if let loaded { self?.applyFlatEdition(cover: loaded, animated: true) }
        }
    }

    private func renderPlaceholder() {
        guard let book = placeholderBook, !holdsVisibleEdition, !isBookTransitionActive else { return }
        let size = bounds.width > 1 && bounds.height > 1 ? bounds.size : CGSize(width: 340, height: 500)
        let scale = max(1, traitCollection.displayScale)
        guard placeholderSize != size || placeholderScale != scale else { return }
        // Render at the actual tile's point size. Rendering a 17pt body label
        // into a fixed large bitmap made the search placeholder illegibly tiny.
        let renderer = ImageRenderer(content: BookPrintedFrontCover(book: book)
            .frame(width: size.width, height: size.height)
            .environment(\.dynamicTypeSize, placeholderDynamicType)
            .environment(\.colorScheme, placeholderColorScheme))
        renderer.scale = scale
        guard let placeholder = renderer.uiImage else { return }
        applyFlatEdition(cover: placeholder)
        placeholderBook = book
        placeholderSize = size
        placeholderScale = scale
    }
}
#endif
