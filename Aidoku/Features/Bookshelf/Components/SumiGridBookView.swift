#if SUMI
import Combine
import Nuke
import NukeUI
import SwiftUI
import UIKit

/// The original cover print, shared unchanged with pickup and return animations.
final class SumiGridBookView: UIImageView, SumiGridBookArtworkProviding {
    private(set) var coverArtwork: UIImage?
    private(set) var bookPose = SumiGridBookPose(seed: 0)
    var renderedBookPose: SumiGridBookPose? { nil }
    private var identity: String?
    private var representedBookID: String?
    private var representedBook: SumiBook?
    private var isBookTransitionActive = false
    private var holdsVisibleEdition = false
    private var refreshOnNextAttachment = false
    private var pendingArtwork: (cover: UIImage, rendered: UIImage, physical: Bool)?
    private var pendingBook: SumiBook?
    private let coverImage = FetchImage()
    private let artworkLoader: SumiCoverArtworkLoader
    private var coverRequestTask: Task<Void, Never>?
    private var sourceLoadedObserver: AnyCancellable?
    private var coverRequestGeneration = UUID()
    private var coverCacheIdentity: AnyHashable?
    private var hasLoadedCover = false
    private var placeholderBook: BookPresentation?
    private var placeholderSize: CGSize = .zero
    private var placeholderScale: CGFloat = 0
    private var placeholderDynamicType: DynamicTypeSize = .large
    private var placeholderColorScheme: ColorScheme = .light

    override convenience init(frame: CGRect) {
        self.init(frame: frame, artworkLoader: .shared)
    }

    init(frame: CGRect, artworkLoader: SumiCoverArtworkLoader) {
        self.artworkLoader = artworkLoader
        super.init(frame: frame)
        contentMode = .scaleAspectFill
        clipsToBounds = true
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        accessibilityIdentifier = "Sumi.Grid.Cover"
        sourceLoadedObserver = NotificationCenter.default.publisher(for: .sourceLoaded)
            .sink { [weak self] notification in
                guard let sourceKey = notification.object as? String else { return }
                Task { @MainActor [weak self] in self?.retryAfterSourceLoaded(sourceKey) }
            }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { coverRequestTask?.cancel() }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !holdsVisibleEdition, !isBookTransitionActive { renderPlaceholder() }
    }

    func beginBookTransition() {
        layer.removeAnimation(forKey: "Sumi.CoverLoaded")
        cancelCoverRequest()
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
            cancelCoverRequest()
            if !isBookTransitionActive { refreshOnNextAttachment = true }
            return
        }
        guard refreshOnNextAttachment, !isBookTransitionActive else {
            refreshOnNextAttachment = false
            refreshPreparedCoverIfNeeded()
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
        refreshPreparedCoverIfNeeded()
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
        let requestedIdentity = "\(book.presentation.id)|\(book.coverURL?.absoluteString ?? "placeholder")"
        let cacheIdentity = artworkLoader.coverIdentity(for: book)
        guard identity != requestedIdentity || coverCacheIdentity != cacheIdentity else {
            representedBook = book
            // Text and reading progress do not change a loaded cover. A
            // generated placeholder can still reflect a newly edited title.
            if !hasLoadedCover, let previous = placeholderBook,
               previous.title != book.title || previous.author != book.presentation.author {
                placeholderBook = book.presentation
                placeholderSize = .zero
                setNeedsLayout()
            }
            refreshPreparedCoverIfNeeded()
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
        cancelCoverRequest()
        hasLoadedCover = false
        representedBookID = book.presentation.id
        representedBook = book
        identity = requestedIdentity
        coverCacheIdentity = cacheIdentity
        bookPose = SumiGridBookPose(seed: book.presentation.placementSeed)
        if let cached = artworkLoader.cachedCover(for: book) {
            hasLoadedCover = true
            applyFlatEdition(cover: cached)
            return
        }
        placeholderBook = book.presentation
        placeholderSize = .zero
        renderPlaceholder()
        refreshPreparedCoverIfNeeded()
    }

    private func retryAfterSourceLoaded(_ sourceKey: String) {
        guard representedBook?.sourceKey == sourceKey, !hasLoadedCover,
              !holdsVisibleEdition, !isBookTransitionActive else { return }
        // A restored source can now supply private-server headers. Restart only
        // its unresolved tile; existing covers and unrelated caches stay intact.
        cancelCoverRequest()
        refreshPreparedCoverIfNeeded()
    }

    private func refreshPreparedCoverIfNeeded() {
        guard !holdsVisibleEdition, !isBookTransitionActive, let book = representedBook else { return }
        let loader = artworkLoader
        if let cached = loader.cachedCover(for: book) {
            hasLoadedCover = true
            if coverArtwork !== cached { applyFlatEdition(cover: cached) }
            return
        }
        // A detached tile keeps its already decoded print, even when the
        // shared reader cache has moved on. Do not restart a completed load.
        guard !hasLoadedCover, coverRequestTask == nil, !coverImage.isLoading,
              book.coverURL != nil, !loader.isInFailureCooldown(for: book) else { return }
        let generation = UUID()
        coverRequestGeneration = generation
        coverRequestTask = Task { @MainActor [weak self] in
            defer {
                if self?.coverRequestGeneration == generation { self?.coverRequestTask = nil }
            }
            guard let request = await loader.coverRequest(for: book), !Task.isCancelled,
                  let self, generation == self.coverRequestGeneration else { return }
            let cacheIdentity = loader.coverIdentity(for: book)
            self.coverCacheIdentity = cacheIdentity
            self.coverImage.onCompletion = { [weak self] result in
                guard let self, generation == self.coverRequestGeneration,
                      self.representedBook?.id == book.id,
                      loader.coverIdentity(for: book) == cacheIdentity else { return }
                switch result {
                case .success(let response):
                    loader.retainVisibleCover(response.image, for: book, request: request)
                    self.hasLoadedCover = true
                    self.applyFlatEdition(cover: response.image, animated: response.cacheType != .memory)
                case .failure:
                    loader.recordVisibleFailure(for: book)
                }
            }
            // NukeUI performs a synchronous memory hit without resetting the
            // image, and coalesces uncached work through the shared pipeline.
            self.coverImage.load(request)
        }
    }

    private func cancelCoverRequest() {
        coverRequestGeneration = UUID()
        coverRequestTask?.cancel()
        coverRequestTask = nil
        coverImage.reset()
    }

    private func renderPlaceholder() {
        guard let book = placeholderBook, !holdsVisibleEdition, !isBookTransitionActive else { return }
        // UIViewRepresentable configures a new tile before SwiftUI gives it a
        // size. Defer that first bitmap instead of drawing a large throwaway
        // placeholder and immediately rendering it again during layout.
        guard bounds.width > 1, bounds.height > 1 else { return }
        let size = bounds.size
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
