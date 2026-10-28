//
//  ReaderViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/14/22.
//

import AidokuRunner
import SafariServices
import SwiftUI
import UIKit

class ReaderViewController: BaseObservingViewController {
    enum Reader {
        case paged
        case scroll
        case text
    }

    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    var chapter: AidokuRunner.Chapter
    var pages: [Page] = []
    var readingMode: ReadingMode = .rtl
    var defaultReadingMode: ReadingMode?
    private var tapZone: TapZone?
    private let temporaryPageStore = ReaderTemporaryPageStore()
    #if SUMI
    private var sumiAllChapters: [AidokuRunner.Chapter] = []
    private var sumiControlsVisible = false
    private var sumiLaysOutControls = false
    private var sumiRequestedToolbarEdge: UIRectEdge?
    private var sumiToolbarRelocation: Task<Void, Never>?
    private var sumiNativeToolbarItem: UIBarButtonItem?
    private var sumiUsesNativeToolbar = false
    private lazy var sumiReaderTitle = SumiReaderTitleView(title: manga.title ?? "Manga")
    private lazy var sumiReaderToolbar: SumiReaderToolbar = {
        let toolbar = SumiReaderToolbar()
        toolbar.mount(sumiScrubber)
        toolbar.close = { [weak self] in self?.close() }
        toolbar.chapters = { [weak self] in self?.sumiShowChapters() }
        toolbar.visibilityDidChange = { [weak self] visible in
            guard let self, sumiUsesNativeToolbar else { return }
            let enabled = visible && sumiControlsVisible && !sumiIsClosing
            navigationController?.toolbar.isUserInteractionEnabled = enabled
        }
        return toolbar
    }()
    private var sumiIsClosing = false
    var sumiIsPreparingOpening = false
    var sumiOpeningFailureMessage: String?
    private var sumiDidCommitPreparedOpening = false
    private var sumiLastVisiblePages: ClosedRange<Int>?
    private lazy var sumiThumbnailLoader = SumiPageThumbnailLoader(mangaKey: manga.key)
    private lazy var sumiScrubber: SumiPageScrubber = {
        let scrubber = SumiPageScrubber()
        scrubber.isHidden = true
        scrubber.previewContainer = self.view
        scrubber.imageProvider = { [weak self] number in
            await self?.sumiScrubberImage(for: number, forHover: false)
        }
        scrubber.hoverImageProvider = { [weak self] number in
            await self?.sumiScrubberImage(for: number, forHover: true)
        }
        scrubber.onCommit = { [weak self] page in self?.sumiGoToPage(page) }
        scrubber.navigateToPage = { [weak self] page in
            guard let self else { return false }
            if let paged = reader as? ReaderPagedViewController {
                return await paged.sumiAnimate(toDisplayPage: page)
            }
            if let vertical = reader as? ReaderWebtoonViewController {
                sumiHideControlsForPageTurn()
                return await vertical.sumiAnimate(toCanonicalPage: page)
            }
            return false
        }
        scrubber.preparePage = { [weak self] page in
            guard let self else { return false }
            if let paged = reader as? ReaderPagedViewController { return await paged.sumiPrepareDisplayPage(page) }
            return reader is ReaderWebtoonViewController
        }
        scrubber.landingSurface = { [weak self] in self?.reader?.view }
        scrubber.isLandingReady = { [weak self] page in
            guard let self else { return false }
            if let paged = reader as? ReaderPagedViewController {
                return paged.sumiIsDisplayPageVisible(page) && paged.sumiReadyForOpening
            }
            if let vertical = reader as? ReaderWebtoonViewController {
                return vertical.sumiIsCanonicalPageVisible(page) && vertical.sumiReadyForOpening
            }
            return false
        }
        return scrubber
    }()

    private func sumiScrubberImage(for number: Int, forHover: Bool) async -> UIImage? {
        let page = (reader as? ReaderPagedViewController)?.sumiPageForScrubber(number) ?? pages[safe: number - 1]
        guard let page, page.chapterId == chapter.key else { return nil }
        return await sumiThumbnailLoader.image(for: page, position: number, source: source, forHover: forHover)
    }
    private(set) var sumiPendingHistorySave: Task<Void, Never>?
    private var sumiHasPresentedActualPage = false
    var sumiOpeningIndex: SumiReaderIndex? {
        didSet { (reader as? ReaderPagedViewController)?.sumiOpeningIndex = sumiOpeningIndex }
    }
    var sumiZoomTargetView: UIView? { (reader as? ReaderPagedViewController)?.sumiZoomTargetView }
    var sumiCurrentCanonicalPage: Int { currentPage }

    private func sumiStopNavigation() {
        (reader as? ReaderPagedViewController)?.sumiStopAnimatedNavigation()
        (reader as? ReaderWebtoonViewController)?.sumiStopAnimatedNavigation()
    }

    func sumiBookDidClose() {
        sumiScrubber.suspendImages()
        Task { await temporaryPageStore.removeAll() }
    }

    func sumiSetBookTransitioning(_ transitioning: Bool) {
        if transitioning {
            sumiScrubber.cancelPreview()
            sumiStopNavigation()
        }
        UIView.animate(withDuration: transitioning ? 0.066 : 0.22, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.sumiReaderToolbar.alpha = transitioning ? 0 : 1
            self.sumiReaderTitle.alpha = transitioning ? 0 : 1
        }
    }

    /// Loading a hidden reader prepares geometry and images only. The opening
    /// transition commits the first actually visible page to reading history.
    func sumiDidOpenPreparedBook() {
        guard !sumiDidCommitPreparedOpening else { return }
        sumiDidCommitPreparedOpening = true
        sumiIsPreparingOpening = false
        becomeFirstResponder()
        sessionStartDate = Date.now
        sessionReadPages = []
        sessionLastInteraction = nil
        guard (toolbarView.totalPages ?? 0) > 0, currentPage >= 1 else { return }
        setCurrentPages(sumiLastVisiblePages ?? currentPage...currentPage)
        showBars()
    }

    func sumiDidShowIndex() {
        // An initial portrait index has not displayed any canonical page yet.
        // Returning here after reading preserves the last real bookmark.
        if !sumiHasPresentedActualPage {
            currentPage = 0
            sessionReadPages = []
        }
        view.accessibilityValue = "Chapter index"
    }

    private func sumiUpdateAccessibilityChildren() {
        // Texture automatically enumerates AS nodes only. Our native controls
        // must be explicit siblings of the reader, rather than disappearing
        // from VoiceOver and UI automation when an AS child is present.
        var elements: [Any] = []
        if let reader, reader.isViewLoaded { elements.append(reader.view!) }
        if sumiControlsVisible {
            elements.append(sumiReaderTitle)
            // A native toolbar is already an accessibility sibling of the
            // content controller. Enumerating it here would expose it twice.
            if !sumiUsesNativeToolbar { elements.append(sumiReaderToolbar) }
            if let overlay = sumiScrubber.accessibilityOverlayView { elements.append(overlay) }
        }
        node.isAccessibilityElement = false
        node.accessibilityElements = elements
    }

    private func sumiSelectIndexChapter(_ selected: AidokuRunner.Chapter) {
        if selected.key == chapter.key, let paged = reader as? ReaderPagedViewController {
            paged.move(toPage: 1, animated: false)
        } else {
            setChapter(selected)
            loadCurrentChapter()
        }
        hideBars()
    }

    private func sumiGoToChapter(_ selected: AidokuRunner.Chapter, resumingTranslation: Bool = false) {
        let startPage: Int
        if resumingTranslation {
            let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: selected.key)
            let savedPage = CoreDataManager.shared.getProgress(chapterId: identifier).progress
            startPage = SumiChapterLanguage.resumePage(savedPage: savedPage, currentPage: currentPage)
        } else {
            startPage = 1
        }
        if selected.key == chapter.key {
            chapter = selected
            reader?.setChapter(selected, startPage: startPage)
        } else {
            setChapter(selected)
            forceStartPage = startPage
            loadCurrentChapter()
        }
        showBars()
    }

    private func sumiGoToPage(_ page: Int) {
        if let paged = reader as? ReaderPagedViewController { paged.sumiMove(toDisplayPage: page) }
        else if let vertical = reader as? ReaderWebtoonViewController, (1...max(1, pages.count)).contains(page) {
            vertical.sumiMove(toCanonicalPage: page)
        }
    }

    private func sumiUpdateReaderControls() {
        guard sumiControlsVisible else { return }
        sumiConfigureNativeControls()
        guard !pages.isEmpty, pages.allSatisfy({ $0.chapterId == chapter.key }) else {
            sumiScrubber.update(chapterKey: chapter.key, totalPages: 0, currentPage: 1, spreads: [])
            return
        }
        sumiScrubber.isReversed = false
        sumiScrubber.reversesThumbnailPages = false
        let paged = reader as? ReaderPagedViewController
        sumiScrubber.update(chapterKey: chapter.key, totalPages: paged?.sumiScrubberPageCount ?? pages.count,
                            currentPage: paged?.sumiScrubberCurrentPage ?? currentPage,
                            spreads: paged?.sumiScrubberSpreads)
    }

    private func sumiConfigureNativeControls() {
        if navigationItem.leftBarButtonItems?.isEmpty == false { navigationItem.leftBarButtonItems = [] }
        if navigationItem.rightBarButtonItems?.isEmpty == false { navigationItem.rightBarButtonItems = [] }
        if navigationItem.titleView != nil { navigationItem.titleView = nil }
        if navigationItem.title != nil { navigationItem.title = nil }
        guard let navigationController else { return }
        if !navigationController.isNavigationBarHidden { navigationController.setNavigationBarHidden(true, animated: false) }
        let usesNative = traitCollection.userInterfaceIdiom != .pad && sumiSystemToolbarEdge != nil
        if #available(iOS 27.1, *), usesNative, let nativeToolbar = navigationController.toolbar {
            if !sumiUsesNativeToolbar {
                sumiReaderToolbar.removeFromSuperview()
                sumiReaderToolbar.axis = .vertical
                sumiReaderToolbar.maximumLength = .greatestFiniteMagnitude
                sumiReaderToolbar.setContentCompressionResistancePriority(.required, for: .horizontal)
                sumiReaderToolbar.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
                sumiReaderToolbar.sizeToFit()
                let item = UIBarButtonItem(customView: sumiReaderToolbar)
                item.axisBehavior = .verticalPreferred
                item.hidesSharedBackground = true
                item.sharesBackground = false
                item.visibilityPriority = .high
                item.isPaddingRemoved = true
                sumiNativeToolbarItem = item
                sumiUsesNativeToolbar = true
                let appearance = UIToolbarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.backgroundColor = .clear
                appearance.backgroundEffect = nil
                appearance.shadowColor = .clear
                nativeToolbar.standardAppearance = appearance
                nativeToolbar.compactAppearance = appearance
                nativeToolbar.scrollEdgeAppearance = appearance
                nativeToolbar.compactScrollEdgeAppearance = appearance
                nativeToolbar.isTranslucent = true
                nativeToolbar.backgroundColor = .clear
                setToolbarItems([item], animated: false)
            }
            if navigationController.isToolbarHidden {
                navigationController.setToolbarHidden(false, animated: false)
            }
            let enabled = sumiControlsVisible && sumiReaderToolbar.isVisible && sumiReaderToolbar.alpha > 0.01 && !sumiIsClosing
            nativeToolbar.isUserInteractionEnabled = enabled
        } else {
            if sumiUsesNativeToolbar {
                sumiNativeToolbarItem?.customView = nil
                sumiNativeToolbarItem = nil
                sumiUsesNativeToolbar = false
                sumiReaderToolbar.removeFromSuperview()
                view.addSubview(sumiReaderToolbar)
                sumiReaderToolbar.maximumLength = .greatestFiniteMagnitude
                sumiReaderToolbar.isUserInteractionEnabled = true
            }
            if toolbarItems?.isEmpty == false { setToolbarItems([], animated: false) }
            navigationController.toolbar.isUserInteractionEnabled = false
            if !navigationController.isToolbarHidden {
                navigationController.setToolbarHidden(true, animated: false)
            }
        }
    }

    private func sumiShowChapters() {
        guard presentedViewController == nil else { return }
        sumiScrubber.cancelPreview()
        sumiStopNavigation()
        let panel = UIHostingController(rootView: SumiReaderChaptersView(
            chapters: sumiAllChapters, currentKey: chapter.key,
            currentPage: currentPage, currentTotalPages: toolbarView.totalPages ?? 0,
            source: source, manga: manga,
            languageSelection: { [weak self] language, chapters in
                guard let self else { return }
                sumiAllChapters = chapters
                chapterList = SumiChapterLanguage.filter(chapters, language: language)
            }, canRead: { [weak self] chapter in
                guard let self else { return false }
                #if DEBUG
                if SumiGridPreviewFixtures.isEnabled && manga.sourceKey == SumiGridPreviewFixtures.sourceKey {
                    return !chapter.locked
                }
                #endif
                let id = ChapterIdentifier(sourceKey: self.manga.sourceKey, mangaKey: self.manga.key, chapterKey: chapter.key)
                return DownloadManager.shared.getDownloadStatus(for: id) == .finished
                    || (source != nil && !chapter.locked)
            }, select: { [weak self] chapter, resumingTranslation in
                self?.dismiss(animated: true) { self?.sumiGoToChapter(chapter, resumingTranslation: resumingTranslation) }
            }, close: { [weak self] in self?.dismiss(animated: true) }
        ))
        panel.view.tintColor = .label
        panel.view.backgroundColor = .systemGroupedBackground
        panel.modalPresentationStyle = .popover
        panel.preferredContentSize = CGSize(width: 340, height: 520)
        panel.popoverPresentationController?.sourceView = sumiReaderToolbar.chaptersAnchorView
        panel.popoverPresentationController?.sourceRect = sumiReaderToolbar.chaptersAnchorView.bounds
        panel.popoverPresentationController?.backgroundColor = .systemGroupedBackground
        present(panel, animated: true)
    }

    private func sumiLayoutReaderControls() {
        guard !sumiLaysOutControls else { return }
        sumiLaysOutControls = true
        defer {
            sumiLaysOutControls = false
            sumiScrubber.updateFloatingLayout()
        }
        let paged = reader as? ReaderPagedViewController
        paged?.sumiOnPageInteraction = { [weak self] in self?.sumiScrubber.cancelPreview() }
        paged?.sumiOnPageTurnBegan = { [weak self] in self?.sumiHideControlsForPageTurn() }
        (reader as? ReaderWebtoonViewController)?.sumiOnPageTurnBegan = { [weak self] in self?.sumiHideControlsForPageTurn() }
        let landscape = view.bounds.width > view.bounds.height
        let isTablet = traitCollection.userInterfaceIdiom == .pad
        let bottomSide = SumiReaderControlsLayout.bottomSide(in: view.bounds,
            isTablet: isTablet, requestedSide: sumiRequestedToolbarEdge)
        let systemSide = isTablet ? nil : sumiSystemToolbarEdge
        let axis: NSLayoutConstraint.Axis = systemSide == nil ? .horizontal : .vertical
        if sumiReaderToolbar.axis != axis {
            sumiToolbarRelocation?.cancel()
            sumiToolbarRelocation = nil
            sumiReaderToolbar.setVisible(sumiControlsVisible, animated: false)
        }
        sumiReaderToolbar.axis = axis
        sumiReaderToolbar.expandsHorizontalStrip = isTablet
        sumiReaderToolbar.sidebarEdge = systemSide ?? bottomSide ?? .right
        sumiConfigureNativeControls()
        var exclusions: [CGRect] = []
        if #available(iOS 27.1, *) {
            exclusions = (view.reservedRegions(kind: .division) + view.reservedRegions(kind: .occlusion))
                .filter(\.isActive).map(\.frame)
        }
        let titleWidth = view.bounds.inset(by: view.safeAreaInsets).width - 16
        sumiReaderTitle.frame = SumiReaderTitleLayout.frame(in: view.bounds, safeAreaInsets: view.safeAreaInsets,
            avoiding: exclusions, size: sumiReaderTitle.preferredSize(availableWidth: titleWidth), side: bottomSide)
        if sumiControlsVisible { view.bringSubviewToFront(sumiReaderTitle) }
        if sumiUsesNativeToolbar, let nativeToolbar = navigationController?.toolbar {
            // UIKit owns the physical column. Only bound our item's length to
            // its public content area; do not infer the column from safe insets.
            let horizontalBounds = nativeToolbar.bounds.width >= nativeToolbar.bounds.height
            let margins = nativeToolbar.layoutMargins
            let length = horizontalBounds ? nativeToolbar.bounds.width - margins.left - margins.right
                : nativeToolbar.bounds.height - margins.top - margins.bottom
            if length > 0 {
                sumiReaderToolbar.maximumLength = max(104, length)
            }
            sumiReaderToolbar.layoutIfNeeded()
            sumiUpdateAccessibilityChildren()
            return
        }
        let toolbarInsets = SumiReaderControlsLayout.toolbarInsets(view.safeAreaInsets,
            systemUsesSideBars: systemSide != nil, ignoresSideInsets: landscape && sumiUsesInnerCanvas)
        let available = axis == .vertical
            ? view.bounds.height - toolbarInsets.top - toolbarInsets.bottom - 16
            : view.bounds.width - toolbarInsets.left - toolbarInsets.right - 16
        let size = sumiReaderToolbar.preferredSize(availableLength: available)
        sumiReaderToolbar.frame = SumiReaderControlsLayout.toolbarFrame(in: view.bounds,
            safeAreaInsets: toolbarInsets, avoiding: exclusions, side: systemSide ?? bottomSide, size: size,
            axis: axis)
        sumiReaderToolbar.layoutIfNeeded()
        sumiUpdateAccessibilityChildren()
    }

    private var sumiSystemToolbarEdge: UIRectEdge? {
        guard #available(iOS 27.1, *) else { return nil }
        // This is the hardware's preferred physical edge, including while the
        // native bars are hidden. Do not infer it from aspect ratio or mirror it.
        let systemEdge: UIRectEdge?
        switch traitCollection.verticalBarEdge {
        case .leading: systemEdge = .left
        case .trailing: systemEdge = .right
        default: systemEdge = nil
        }
        return SumiReaderControlsLayout.sidebarEdge(systemEdge: systemEdge, hasInnerFold: sumiUsesInnerCanvas)
    }

    private var sumiUsesInnerCanvas: Bool {
        guard #available(iOS 27.1, *) else { return false }
        // Inactive division regions identify the inner canvas even when the
        // book is fully open and its fold currently has zero width.
        return !view.reservedRegions(kind: .division, options: .includeInactive).isEmpty
    }

    private func sumiHideControlsForPageTurn() {
        sumiToolbarRelocation?.cancel()
        sumiToolbarRelocation = nil
        sumiControlsVisible = false
        sumiSetStatusBarHidden(true)
        sumiReaderToolbar.setVisible(false, animated: !UIAccessibility.isReduceMotionEnabled)
        sumiReaderTitle.setVisible(false, animated: !UIAccessibility.isReduceMotionEnabled)
        sumiUpdateAccessibilityChildren()
        NotificationCenter.default.post(name: .readerHidingBars, object: nil)
    }

    private func sumiSetStatusBarHidden(_ hidden: Bool) {
        guard statusBarHidden != hidden else { return }
        statusBarHidden = hidden
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.2) {
            self.setNeedsStatusBarAppearanceUpdate()
            self.navigationController?.setNeedsStatusBarAppearanceUpdate()
        } completion: { [weak self] _ in
            // Refresh native bar geometry after the status presentation settles.
            guard let self else { return }
            UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.12,
                           delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
                self.sumiLayoutReaderControls()
            }
        }
    }

    private func sumiHandlePageTap(at point: CGPoint) {
        guard traitCollection.userInterfaceIdiom != .pad,
              sumiSystemToolbarEdge == nil, view.bounds.width > view.bounds.height else {
            toggleBarVisibility()
            return
        }
        let side: UIRectEdge = point.x < view.bounds.midX ? .left : .right
        let currentSide = sumiReaderToolbar.sidebarEdge
        if sumiControlsVisible, currentSide != side {
            sumiToolbarRelocation?.cancel()
            sumiReaderToolbar.setVisible(false, animated: !UIAccessibility.isReduceMotionEnabled)
            sumiToolbarRelocation = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                guard let self, !Task.isCancelled else { return }
                sumiRequestedToolbarEdge = side
                sumiLayoutReaderControls()
                sumiReaderToolbar.setVisible(true, animated: !UIAccessibility.isReduceMotionEnabled)
                sumiToolbarRelocation = nil
            }
        } else {
            sumiRequestedToolbarEdge = side
            toggleBarVisibility()
        }
    }

    #endif

    private var chapterList: [AidokuRunner.Chapter]
    private var chaptersToMark: [AidokuRunner.Chapter] = []
    private var chaptersToRemoveDownload: [AidokuRunner.Chapter] = [] {
        didSet {
            // ensure chapters queued for deletion are persistent, in case of app termination
            if chaptersToRemoveDownload.isEmpty {
                UserDefaults.standard.removeObject(forKey: "Data.chaptersToBeDeleted")
            } else {
                let data = try? JSONEncoder().encode(chaptersToRemoveDownload.map {
                    ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: $0.key)
                })
                UserDefaults.standard.set(data, forKey: "Data.chaptersToBeDeleted")
            }
        }
    }
    private var forceStartPage: Int?
    private var currentPage = 1
    private var currentPosition: Double?
    private var sessionReadPages: Set<Int> = []
    private var sessionStartDate: Date?
    private var sessionLastInteraction: Date?

    weak var reader: ReaderReaderDelegate?

    // Dictionary popup state
    private lazy var dictionaryCoordinator = ReaderDictionaryCoordinator(owner: self)
    private var _dictionaryLongPressSelection: Any?
    @available(iOS 18.0, *)
    private var dictionaryLongPressSelection: TextRecognizer.Result? {
        get { _dictionaryLongPressSelection as? TextRecognizer.Result }
        set { _dictionaryLongPressSelection = newValue }
    }
    private var isDictionaryOCRActiveForCurrentChapter: Bool {
        #if SUMI
        false
        #else
        AppSettings.dictionary.isOCREnabled(language: chapter.language ?? source?.languages.first)
        #endif
    }
    private var isDictionarySingleTapLookupActiveForCurrentChapter: Bool {
        AppSettings.dictionary.lookupGesture.get() == .singleTap && isDictionaryOCRActiveForCurrentChapter
    }
    private var isDictionaryLongPressLookupActiveForCurrentChapter: Bool {
        AppSettings.dictionary.lookupGesture.get() == .longPress && isDictionaryOCRActiveForCurrentChapter
    }

    private lazy var activityIndicator = UIActivityIndicatorView(style: .medium)
    private lazy var toolbarView = ReaderToolbarView()
    private lazy var pageSizingButton = UIBarButtonItem(
        title: NSLocalizedString("PAGE_SIZING"),
        image: UIImage(systemName: "arrow.up.left.and.arrow.down.right"),
        primaryAction: nil,
        menu: ReaderPageSizingMenu.makeMenu()
    )
    private var toolbarViewWidthConstraint: NSLayoutConstraint?

    private var squeezeTimer: Timer?
    private var longSqueezeTimer: Timer?
    private var squeezeStartTime: Date?
    private let doubleSqueezeInterval: TimeInterval = 0.3
    private let longSqueezeThreshold: TimeInterval = 0.5

    private lazy var autoScrollButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        if #available(iOS 26.0, *) {
            configuration = .glass()
        } else {
            configuration = .filled()
            configuration.baseBackgroundColor = .secondarySystemBackground
            configuration.baseForegroundColor = .label
        }
        configuration.cornerStyle = .capsule
        configuration.image = UIImage(systemName: "play.fill")
        configuration.contentInsets = .init(top: 10, leading: 10, bottom: 10, trailing: 10)

        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: #selector(toggleAutoScroll), for: .touchUpInside)
        button.addTarget(self, action: #selector(autoScrollButtonTouchDown), for: .touchDown)
        button.addTarget(
            self,
            action: #selector(autoScrollButtonTouchEnded),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()
    private var isInteractingWithAutoScrollButton = false
    private lazy var autoScrollButtonLeadingConstraint =
        autoScrollButton.leadingAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.leadingAnchor,
            constant: 16
        )
    private lazy var autoScrollButtonTrailingConstraint =
        autoScrollButton.trailingAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.trailingAnchor,
            constant: -16
        )

    private lazy var descriptionButtonController: UIHostingController<ReaderPageDescriptionButtonView> = {
        let buttonView = ReaderPageDescriptionButtonView(source: source, pages: [])
        let hostingController = UIHostingController(rootView: buttonView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.alpha = 0
        hostingController.view.isHidden = true
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        return hostingController
    }()
    private lazy var descriptionTrailingConstraint =
        descriptionButtonController.view.trailingAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.trailingAnchor,
            constant: -16
        )
    private lazy var descriptionTrailingToAutoScrollConstraint =
        descriptionButtonController.view.trailingAnchor.constraint(
            equalTo: autoScrollButton.leadingAnchor,
            constant: -16
        )

    private var barToggleTapGesture: UITapGestureRecognizer?
    private var barToggleSecondaryTapGesture: UITapGestureRecognizer?
    private var barDismissNavigationBarTapGesture: UITapGestureRecognizer?
    private var dictionaryLongPressGesture: UILongPressGestureRecognizer?

    #if SUMI
    var statusBarHidden = true
    #else
    var statusBarHidden = false
    #endif

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        UIStatusBarAnimation.fade
    }
    override var prefersStatusBarHidden: Bool {
        statusBarHidden
    }
    override var prefersHomeIndicatorAutoHidden: Bool {
        statusBarHidden
    }

    init(
        source: AidokuRunner.Source?,
        manga: AidokuRunner.Manga,
        chapter: AidokuRunner.Chapter,
        startPage: Int? = nil
    ) {
        self.source = source
        self.manga = manga
        self.chapter = chapter
        self.chapterList = manga.chapters ?? []
        #if SUMI
        self.sumiAllChapters = manga.chapters ?? []
        self.chapterList = SumiChapterLanguage.filter(sumiAllChapters,
            language: SumiChapterLanguage.activeLanguage(chapters: sumiAllChapters, currentChapter: chapter,
                preferred: SumiChapterLanguage.persistedLanguage(mangaID: manga.identifier)))
        #endif
        self.chaptersToMark = [chapter]
        self.defaultReadingMode = switch manga.viewer {
            case .rightToLeft: .rtl
            case .leftToRight: .ltr
            case .vertical: .vertical
            case .webtoon: .webtoon
            case .unknown: .none
        }
        self.forceStartPage = startPage
        super.init()
    }

    deinit {
        Task { [temporaryPageStore] in
            await temporaryPageStore.removeAll()
        }
    }

    override func configure() {
        // Keep the reader's bounds stable as navigation and toolbars toggle.
        // Artwork draws underneath them; controls remain inside the safe area.
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true
        #if SUMI
        node.backgroundColor = SumiPaperSurface.backgroundColor
        #else
        node.backgroundColor = .systemBackground
        #endif
        navigationController?.navigationBar.prefersLargeTitles = false
        #if SUMI
        view.accessibilityIdentifier = "Sumi.DirectReader"
        view.accessibilityValue = "Loading chapter"
        #endif

        // navbar buttons
        navigationItem.leftBarButtonItems = [
            UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(close)
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "list.bullet"),
                style: .plain,
                target: self,
                action: #selector(openChapterList)
            )
        ]
        #if SUMI
        navigationItem.leftBarButtonItems = []
        navigationItem.rightBarButtonItems = []
        #else
        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "safari"),
            style: .plain,
            target: self,
            action: #selector(openWebView)
        )
        moreButton.isEnabled = chapter.url != nil
        navigationItem.rightBarButtonItems = [
            moreButton,
            UIBarButtonItem(
                image: UIImage(systemName: "textformat.size"),
                style: .plain,
                target: self,
                action: #selector(openReaderSettings)
            )
        ]
        #endif

        // fix navbar being clear
        let navigationBarAppearance = UINavigationBarAppearance()
        let toolbarAppearance = UIToolbarAppearance()
        navigationBarAppearance.configureWithDefaultBackground()
        toolbarAppearance.configureWithDefaultBackground()
        navigationController?.navigationBar.standardAppearance = navigationBarAppearance
        navigationController?.navigationBar.compactAppearance = navigationBarAppearance
        navigationController?.navigationBar.scrollEdgeAppearance = navigationBarAppearance
        navigationController?.toolbar.standardAppearance = toolbarAppearance
        navigationController?.toolbar.compactAppearance = toolbarAppearance
        navigationController?.toolbar.scrollEdgeAppearance = toolbarAppearance

        loadNavbarTitle()

        // toolbar view
        toolbarView.sliderView.addTarget(self, action: #selector(sliderMoved(_:)), for: .valueChanged)
        toolbarView.sliderView.addTarget(self, action: #selector(sliderStopped(_:)), for: .editingDidEnd)
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        let toolbarButtonItemView = UIBarButtonItem(customView: toolbarView)
        toolbarButtonItemView.customView?.heightAnchor.constraint(equalToConstant: 40).isActive = true
        if #available(iOS 26.0, *) {
            toolbarViewWidthConstraint = toolbarButtonItemView.customView?.widthAnchor.constraint(
                equalToConstant: node.bounds.width - 32 - 10
            )
            // shift down farther to account for different toolbar and slider knob size
            toolbarButtonItemView.customView?.transform = CGAffineTransform(translationX: 0, y: -5)
        } else {
            toolbarViewWidthConstraint = toolbarButtonItemView.customView?.widthAnchor.constraint(equalToConstant: view.bounds.width)
            toolbarButtonItemView.customView?.transform = CGAffineTransform(translationX: 0, y: -10)
        }

        add(child: descriptionButtonController)
        view.addSubview(autoScrollButton)

        #if SUMI
        toolbarItems = []
        navigationController?.setNavigationBarHidden(true, animated: false)
        navigationController?.setToolbarHidden(true, animated: false)
        #else
        toolbarItems = [toolbarButtonItemView]
        navigationController?.isToolbarHidden = false
        navigationController?.toolbar.fitContentViewToToolbar()
        #endif

        // loading indicator
        activityIndicator.startAnimating()
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        #if SUMI
        view.addSubview(sumiReaderToolbar)
        view.addSubview(sumiReaderTitle)
        if #available(iOS 27.1, *) {
            registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) {
                (self: ReaderViewController, _: UITraitCollection) in self.view.setNeedsLayout()
            }
        }
        #endif

        // initialize dictionary engine
        if
            #available(iOS 18.0, *),
            AppSettings.dictionary.enable.get()
                {
            DictionaryManager.shared.rebuildLookupQuery()
        }
        configureDictionaryLookupGesture()
        configureDictionaryOverlayInteractionMode()

        // bar toggle tap gesture
        configureBarToggleTapGestures()

        // page offset tap gesture
        let pageOffsetGesture = UITapGestureRecognizer(target: self, action: #selector(toggleOffset))
        pageOffsetGesture.numberOfTouchesRequired = 2
        pageOffsetGesture.numberOfTapsRequired = 2
        view.addGestureRecognizer(pageOffsetGesture)

        // set reader
        let readingModeKey = "Reader.readingMode.\(manga.identifier)"
        UserDefaults.standard.register(defaults: [readingModeKey: "default"])
        #if SUMI
        setReadingMode("auto")
        #else
        setReadingMode(UserDefaults.standard.string(forKey: readingModeKey))
        #endif

        // set up apple pencil squeeze handler
        if #available(iOS 17.5, *) {
            let pencilInteraction = UIPencilInteraction(delegate: self)
            view.addInteraction(pencilInteraction)
        }

        // load current tap zone
        updateTapZone()

        // load chapter list
        #if SUMI
        hideBars()
        #endif
        loadCurrentChapter()
    }

    override func constrain() {
        toolbarViewWidthConstraint?.isActive = true

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            descriptionButtonController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            autoScrollButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        updateAutoScrollButton()
    }

    override func observe() {
        addObserver(forName: AppSettings.reader.pageSizing.key) { [weak self] _ in
            self?.pageSizingButton.menu = ReaderPageSizingMenu.makeMenu()
        }
        addObserver(forName: "Reader.readingMode.\(manga.identifier)") { [weak self] _ in
            guard let self else { return }
            #if SUMI
            self.setReadingMode("auto")
            #else
            self.setReadingMode(UserDefaults.standard.string(forKey: "Reader.readingMode.\(self.manga.identifier)"))
            #endif
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
            // if the tap zone is auto, it will changed based on the current reader
            self.updateTapZone()
        }
        addObserver(forName: "Reader.disableDoubleTap") { [weak self] _ in
            self?.configureBarToggleTapGestures()
        }
        addObserver(forName: "Reader.autoScroll") { [weak self] _ in
            self?.updateAutoScrollButton()
        }
        addObserver(forName: .readerTapZones) { [weak self] _ in
            self?.updateTapZone()
        }
        let reloadBlock: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
        }
        // reload pages when processors change
        addObserver(forName: "Reader.downsampleImages", using: reloadBlock)
        addObserver(forName: "Reader.upscaleImages", using: reloadBlock)
        addObserver(forName: AppSettings.reader.upscaleQuality.key, using: reloadBlock)
        addObserver(forName: "Reader.cropBorders", using: reloadBlock)
        addObserver(forName: "Reader.liveText", using: reloadBlock)
        addObserver(forName: AppSettings.dictionary.overlayPadding.key, using: reloadBlock)
        addObserver(forName: AppSettings.dictionary.overlayTextScaleMultiplier.key, using: reloadBlock)
        let dictionaryReloadBlock: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            self.configureBarToggleTapGestures()
            self.configureDictionaryLookupGesture()
            self.configureDictionaryOverlayInteractionMode()
            self.reader?.setChapter(self.chapter, startPage: self.currentPage)
        }
        for key in [
            AppSettings.dictionary.enable.key,
            AppSettings.dictionary.lookupGesture.key,
            AppSettings.dictionary.textOverlayMode.key,
            AppSettings.dictionary.restrictOCRLanguages.key,
            AppSettings.dictionary.restrictedOCRLanguages.key
        ] {
            addObserver(forName: key, using: dictionaryReloadBlock)
        }
        addObserver(forName: .dictionaryDictionariesChanged, using: dictionaryReloadBlock)
        // Switch text reader style (paged <-> scroll) without restart
        addObserver(forName: "Reader.textReaderStyle") { [weak self] _ in
            guard let self else { return }
            // Only switch if we're currently in a text reader
            if self.reader is ReaderTextViewController || self.reader is ReaderPagedTextViewController {
                // Save current position before switching so the new reader can restore it
                Task {
                    await self.updateReadPosition()
                    await MainActor.run {
                        self.setReader(.text)
                        self.reader?.setChapter(self.chapter, startPage: self.currentPage)
                        self.updateTapZone()
                    }
                }
            }
        }
        addObserver(forName: ReaderTextTheme.changeNotification) { [weak self] _ in
            self?.updateTextThemeOverride()
        }
        addObserver(forName: UIScene.willDeactivateNotification) { [weak self] _ in
            guard let self else { return }
            #if SUMI
            sumiQueueReadPositionSave()
            #else
            Task {
                await self.updateReadPosition()
            }
            #endif

            #if SUMI
            statusBarHidden = true
            #else
            if #available(iOS 26.0, *) {
                statusBarHidden = false
            }
            #endif
        }
        addObserver(forName: UIScene.didActivateNotification) { [weak self] _ in
            guard let self else { return }
            #if SUMI
            self.hideBars()
            guard !self.sumiIsPreparingOpening else { return }
            #endif
            if self.sessionStartDate == nil {
                #if SUMI
                self.sessionReadPages = self.currentPage >= 1 ? [self.currentPage] : []
                #else
                self.sessionReadPages = [self.currentPage]
                #endif
                self.sessionStartDate = Date.now
                self.sessionLastInteraction = nil
            }
        }
        if #available(iOS 26.0, *) {
            addObserver(forName: UIScene.willEnterForegroundNotification) { [weak self] _ in
                if self?.navigationController?.toolbar.alpha == 0 {
                    self?.hideBars()
                }
            }
        }
        addObserver(forName: "Reader.autoScroll") { [weak self] _ in
            self?.updateAutoScrollButton()
        }
        addObserver(forName: AppSettings.reader.autoScrollPosition.key) { [weak self] _ in
            guard let self else { return }
            let visible = self.reader is ReaderWebtoonViewController && UserDefaults.standard.bool(forKey: "Reader.autoScroll")
            self.updateAutoScrollButtonPosition(visible: visible, animated: true)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if SUMI
        sumiIsClosing = false
        #endif

        #if SUMI
        sessionReadPages = !sumiIsPreparingOpening && currentPage >= 1 ? [currentPage] : []
        sessionStartDate = sumiIsPreparingOpening ? nil : Date.now
        #else
        sessionReadPages = [self.currentPage]
        sessionStartDate = Date.now
        #endif
        sessionLastInteraction = nil

        #if SUMI
        if sumiIsPreparingOpening || !sumiDidCommitPreparedOpening { hideBars() }
        else { showBars() }
        #else
        if navigationController?.toolbar.alpha == 0 {
            hideBars()
        }

        // there's a bug on ios 15 where the toolbar just disappears when adding a child hosting controller
        navigationController?.isToolbarHidden = false
        navigationController?.toolbar.alpha = 1
        #endif

        disableSwipeGestures()
        configureNavigationBarDismissTapGesture(enabled: isDictionarySingleTapLookupActiveForCurrentChapter)

        // resume auto scroll if it was paused when presenting a sheet
        if let reader = reader as? ReaderWebtoonViewController {
            reader.resumeAutoScroll()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        (reader as? ReaderWebtoonViewController)?.stopAutoScroll()

        if !chaptersToRemoveDownload.isEmpty {
            Task {
                await DownloadManager.shared.delete(chapters: chaptersToRemoveDownload.map {
                    .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: $0.key)
                })
                chaptersToRemoveDownload = []
            }
        }

        #if SUMI
        sumiScrubber.cancelPreview()
        sumiStopNavigation()
        guard !sumiIsClosing, !sumiIsPreparingOpening else { return }
        #endif
        guard currentPage >= 1 else { return }
        #if SUMI
        sumiQueueReadPositionSave()
        #else
        Task {
            await updateReadPosition()
        }
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        #if SUMI
        if let reader, reader.view.frame != view.bounds { reader.view.frame = view.bounds }
        sumiLayoutReaderControls()
        #endif
        updateReaderToolbarLayout()
        displaceReaderControls()
        dictionaryCoordinator.updateLayout()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        dictionaryCoordinator.updateLayout()
        view.setNeedsLayout()
    }

    private func updateReaderToolbarLayout() {
        guard let toolbar = navigationController?.toolbar, toolbar.bounds.width > 0 else { return }
        let safeBounds = toolbar.bounds.inset(by: toolbar.safeAreaInsets)
        var availableBounds = safeBounds
        if #available(iOS 27.1, *) {
            let exclusions = (toolbar.reservedRegions(kind: .division) + toolbar.reservedRegions(kind: .occlusion))
                .filter(\.isActive).map(\.frame)
            availableBounds = ReaderControlLayout.availableRegions(in: safeBounds, avoiding: exclusions)
                .filter { $0.height >= min(40, safeBounds.height) }
                .max(by: { $0.width < $1.width }) ?? safeBounds
        }
        let padding: CGFloat = if #available(iOS 26.0, *) { 42 } else { 0 }
        toolbarViewWidthConstraint?.constant = max(0, availableBounds.width - padding)
        let yOffset: CGFloat = if #available(iOS 26.0, *) { -5 } else { -10 }
        toolbarView.transform = CGAffineTransform(
            translationX: availableBounds.midX - toolbar.bounds.midX,
            y: yOffset
        )
    }

    private func displaceReaderControls() {
        guard #available(iOS 27.1, *) else { return }
        #if SUMI
        let controls: [UIView] = []
        #else
        let controls = [autoScrollButton, descriptionButtonController.view!]
        #endif
        controls.forEach { $0.transform = .identity }
        let visibleControls = controls.filter { !$0.isHidden && $0.alpha > 0 }
        guard let firstControl = visibleControls.first else { return }
        let frame = visibleControls.dropFirst().reduce(firstControl.frame) { $0.union($1.frame) }
        let exclusions = (view.reservedRegions(kind: .division) + view.reservedRegions(kind: .occlusion))
            .filter(\.isActive).map(\.frame)
        let offset = ReaderControlLayout.offset(for: frame, inside: view.safeAreaLayoutGuide.layoutFrame, avoiding: exclusions)
        visibleControls.forEach { $0.transform = CGAffineTransform(translationX: offset.x, y: offset.y) }
    }
}

extension ReaderViewController {
    func disableSwipeGestures() {
        let isVerticalReader = reader is ReaderWebtoonViewController || readingMode == .vertical

        // the view with the target gesture recognizers changes based on if it was presented from uikit or swiftui
        let gestureRecognizers = (parent?.view.gestureRecognizers ?? []) + (parent?.view.superview?.superview?.gestureRecognizers ?? [])

        for recognizer in gestureRecognizers {
            switch String(describing: type(of: recognizer)) {
                case "_UIParallaxTransitionPanGestureRecognizer": // swipe edge gesture
                    recognizer.isEnabled = isVerticalReader

                case "_UIContentSwipeDismissGestureRecognizer": // swipe down gesture
                    recognizer.isEnabled = !isVerticalReader
                    recognizer.delegate = self // ensure gesture only activates on swipe down, not swipe right

//                case "_UITransformGestureRecognizer": // pinch gesture
//                    recognizer.isEnabled = true

                default:
                    break
            }
        }
    }

    #if SUMI
    /// Capture the visible chapter before any suspension. A chapter still loading
    /// has no bookmark, and an older save must never consume a newer session.
    private func sumiQueueReadPositionSave() {
        guard !sumiIsPreparingOpening, sumiHasPresentedActualPage,
              currentPage >= 1, let total = toolbarView.totalPages, total > 0 else { return }
        let page = currentPage
        let position = currentPosition
        let chapter = self.chapter
        let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key)
        let start = sessionStartDate
        let end = Date.now
        let pagesRead = sessionReadPages.count
        let hadInteraction = sessionLastInteraction != nil
        let incognito = AppSettings.general.incognitoMode.get()
        sessionStartDate = nil
        let previous = sumiPendingHistorySave
        sumiPendingHistorySave = Task {
            await previous?.value
            guard !incognito else { return }
            let completed = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
                CoreDataManager.shared.getProgress(chapterId: identifier, context: context).0
            }
            await HistoryManager.shared.setProgress(chapterId: identifier, chapter: chapter,
                progress: page, totalPages: total, scrollPosition: position, completed: completed)
            if let start, pagesRead > 0, hadInteraction {
                await HistoryManager.shared.addSession(chapterId: identifier,
                    data: .init(startDate: start, endDate: end, pagesRead: pagesRead))
            }
        }
    }
    #endif

    func updateReadPosition(
        currentPage: Int? = nil,
        totalPages: Int? = nil,
        chapter: AidokuRunner.Chapter? = nil
    ) async {
        #if SUMI
        sumiQueueReadPositionSave()
        await sumiPendingHistorySave?.value
        #else
        let effectiveTotalPages = totalPages ?? toolbarView.totalPages ?? 0
        let effectiveCurrentPage = currentPage ?? self.currentPage
        #if SUMI
        guard !sumiIsPreparingOpening, effectiveCurrentPage >= 1 else { return }
        #endif

        guard
            !AppSettings.general.incognitoMode.get(),
            effectiveTotalPages > 0 // ensure chapter pages are loaded
        else {
            return
        }

        let currentPage = effectiveCurrentPage
        let chapter = chapter ?? self.chapter

        let chapterId = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key)
        let (completed, progress) = await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
            CoreDataManager.shared.getProgress(
                chapterId: chapterId,
                context: context
            )
        }
        let hasHistory = completed || progress != nil

        // don't add history if there is none and we're at the first page
        #if !SUMI
        if currentPage == 1 && !hasHistory {
            return
        }
        #endif

        await HistoryManager.shared.setProgress(
            chapterId: chapterId,
            chapter: chapter,
            progress: currentPage,
            totalPages: effectiveTotalPages,
            scrollPosition: currentPosition,
            completed: completed
        )
        await saveReadingSession(chapter: chapter)
        #endif
    }

    private func saveReadingSession(chapter: AidokuRunner.Chapter? = nil) async {
        guard let sessionStartDate else { return }
        let pagesRead = sessionReadPages.count
        if pagesRead > 0 && sessionLastInteraction != nil {
            let chapter = chapter ?? self.chapter
            await HistoryManager.shared.addSession(
                chapterId: .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: chapter.key),
                data: .init(startDate: sessionStartDate, endDate: .now, pagesRead: pagesRead)
            )
        }
        self.sessionStartDate = nil
    }

    func loadChapterList() async {
        let updatedManga = try? await source?.getMangaUpdate(
            manga: manga,
            needsDetails: false,
            needsChapters: true
        )
        #if SUMI
        if let fetched = updatedManga?.chapters {
            sumiAllChapters = SumiChapterLanguage.merge(sumiAllChapters, with: fetched)
            chapterList = SumiChapterLanguage.filter(sumiAllChapters,
                language: SumiChapterLanguage.activeLanguage(chapters: sumiAllChapters, currentChapter: chapter,
                    preferred: SumiChapterLanguage.persistedLanguage(mangaID: manga.identifier)))
        }
        sumiUpdateReaderControls()
        #else
        chapterList = updatedManga?.chapters ?? []
        #endif
    }

    func loadCurrentChapter() {
        if chapterList.isEmpty {
            Task {
                await loadChapterList()
            }
        }

        if let forceStartPage {
            currentPage = forceStartPage
            self.forceStartPage = nil
        } else {
            let (completed, startPage) = CoreDataManager.shared.getProgress(
                chapterId: .init(
                    sourceKey: manga.sourceKey,
                    mangaKey: manga.key,
                    chapterKey: chapter.key
                )
            )
            if !completed, let startPage {
                currentPage = startPage
            } else {
                currentPage = -1
            }
        }
        reader?.setChapter(chapter, startPage: currentPage)
    }

    func loadNavbarTitle() {
        #if SUMI
        navigationItem.titleView = nil
        navigationItem.title = nil
        return
        #endif
        let volume: String? =
            if chapter.chapterNumber != nil, let volumeNum = chapter.volumeNumber {
                String(format: NSLocalizedString("VOLUME_X"), volumeNum)
            } else {
                nil
            }

        let title =
            if let chapterNum = chapter.chapterNumber {
                String(format: NSLocalizedString("CHAPTER_X"), chapterNum)
            } else if let volumeNum = chapter.volumeNumber {
                String(format: NSLocalizedString("VOLUME_X"), volumeNum)
            } else {
                chapter.title ?? ""
            }

        navigationItem.setTitle(upper: volume, lower: title)
        // re-apply theme title colors, since setTitle recreates the title view
        updateTextThemeOverride()
    }

    func showLoadFailAlert() {
        #if SUMI
        // An offscreen reader must never present a modal alert over the
        // loading host: that steals its outside-tap cancellation gestures.
        if sumiIsPreparingOpening {
            sumiOpeningFailureMessage = String(localized: "The source returned no readable pages for this chapter.")
            return
        }
        #endif
        let alert = UIAlertController(
            title: NSLocalizedString("FAILED_CHAPTER_LOAD"),
            message: NSLocalizedString("FAILED_CHAPTER_LOAD_INFO"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK"), style: .cancel))
        present(alert, animated: true)
    }

    @objc func openReaderSettings() {
        (reader as? ReaderWebtoonViewController)?.stopAutoScroll()

        let currentReader: Reader
        switch reader {
            case is ReaderTextViewController, is ReaderPagedTextViewController:
                currentReader = .text
            case is ReaderPagedViewController:
                currentReader = .paged
            case is ReaderWebtoonViewController:
                currentReader = .scroll
            default:
                currentReader = .paged
        }
        let vc = UIHostingController(
            rootView: ReaderSettingsView(
                mangaId: manga.identifier,
                reader: currentReader,
                chapterLanguage: chapter.language ?? source?.languages.first
            )
        )
        if currentReader == .text {
            vc.overrideUserInterfaceStyle = ReaderTextTheme.getInterfaceStyleOverride()
        }
        present(vc, animated: true)
    }

    @objc func openWebView() {
        guard let url = chapter.url, url.scheme == "http" || url.scheme == "https" else { return }
        (reader as? ReaderWebtoonViewController)?.stopAutoScroll()
        present(SFSafariViewController(url: url), animated: true)
    }

    @objc func openChapterList() {
        #if SUMI
        if !sumiControlsVisible { showBars() }
        sumiShowChapters()
        #else
        (reader as? ReaderWebtoonViewController)?.stopAutoScroll()

        var view = ReaderChapterListView(
            chapterList: chapterList,
            chapter: chapter
        )
        view.chapterSet = { [weak self] chapter in
            guard let self else { return }
            if chapter != self.chapter {
                self.setChapter(chapter)
                self.loadCurrentChapter()
            }
        }
        present(UIHostingController(rootView: view), animated: true)
        #endif
    }

    @objc func close() {
        #if SUMI
        guard !sumiIsClosing else { return }
        sumiIsClosing = true
        sumiScrubber.cancelPreview()
        sumiStopNavigation()
        Task {
            // A grid retap may happen immediately after dismissal. Commit the
            // real chapter/page before making the grid interactive again.
            await sumiPendingHistorySave?.value
            await updateReadPosition()
            var owner: UIViewController = self
            while let parent = owner.parent { owner = parent }
            dismiss(animated: true) { [weak self, weak owner, temporaryPageStore] in
                guard owner?.presentingViewController == nil else {
                    self?.sumiIsClosing = false
                    return
                }
                // Keep temporary page images alive for the reverse zoom.
                Task { await temporaryPageStore.removeAll() }
            }
        }
        #else
        Task {
            await temporaryPageStore.removeAll()
        }
        dismiss(animated: true)
        #endif
    }

    @objc func sliderMoved(_ sender: ReaderSliderView) {
        reader?.sliderMoved(value: sender.currentValue)
    }
    @objc func sliderStopped(_ sender: ReaderSliderView) {
        reader?.sliderStopped(value: sender.currentValue)
    }
}

// MARK: - Reading Mode
extension ReaderViewController {
    func setReadingMode(_ mode: String?) {
        switch mode {
            case "rtl": readingMode = .rtl
            case "ltr": readingMode = .ltr
            case "vertical": readingMode = .vertical
            case "scroll", "webtoon": readingMode = .webtoon
            case "continuous": readingMode = .continuous
            case "default":
                let defaultMode = UserDefaults.standard.string(forKey: "Reader.readingMode")
                if defaultMode == "default" {
                    setReadingMode("auto")
                } else {
                    setReadingMode(defaultMode)
                }
                return
            default: // auto
                // use given default reading mode
                if let defaultReadingMode {
                    readingMode = defaultReadingMode
                } else if CoreDataManager.shared.hasManga(mangaId: manga.identifier) {
                    // fall back to stored manga viewer
                    let sourceMode = CoreDataManager.shared.getMangaSourceReadingMode(mangaId: manga.identifier)
                    if let mode = ReadingMode(rawValue: sourceMode) {
                        readingMode = mode
                    } else {
                        readingMode = .rtl
                    }
                } else {
                    // fall back to rtl reading mode
                    readingMode = .rtl
                }
        }

        #if SUMI
        // The source determines whether this is a bound book or a vertical strip.
        // Vertical manga scrolls with page spacing; webtoons remain continuous.
        if readingMode == .vertical { readingMode = .continuous }
        #endif
        if !(reader is ReaderTextViewController) {
            switch readingMode {
                case .ltr, .rtl, .vertical:
                    setReader(.paged)
                case .webtoon, .continuous:
                    setReader(.scroll)
            }
        }
    }

    func setReader(_ type: Reader) {
        var barItems = navigationItem.rightBarButtonItems ?? []
        barItems.removeAll { $0 === pageSizingButton }
        #if !SUMI
        if type == .paged {
            barItems.append(pageSizingButton)
        }
        #endif
        navigationItem.rightBarButtonItems = barItems
        let pageController: ReaderReaderDelegate?
        switch type {
            case .paged:
                if readingMode == .rtl {
                    toolbarView.sliderView.direction = .backward
                } else {
                    toolbarView.sliderView.direction = .forward
                }
                if !(reader is ReaderPagedViewController) {
                    pageController = ReaderPagedViewController(source: source, manga: manga, temporaryPageStore: temporaryPageStore)
                } else {
                    pageController = nil
                }
            case .scroll:
                toolbarView.sliderView.direction = .forward
                if !(reader is ReaderWebtoonViewController) {
                    pageController = ReaderWebtoonViewController(source: source, manga: manga, temporaryPageStore: temporaryPageStore)
                } else {
                    pageController = nil
                }
            case .text:
                // Text always reads left-to-right, regardless of manga setting
                toolbarView.sliderView.direction = .forward

                // Check user preference for text reader style
                let textReaderStyle = UserDefaults.standard.string(forKey: "Reader.textReaderStyle") ?? "paged"
                if textReaderStyle == "paged" {
                    // Kindle-like paginated experience
                    if !(reader is ReaderPagedTextViewController) {
                        pageController = ReaderPagedTextViewController(source: source, manga: manga)
                    } else {
                        pageController = nil
                    }
                } else {
                    // Original scroll-based text reader
                    if !(reader is ReaderTextViewController) {
                        pageController = ReaderTextViewController(source: source, manga: manga)
                    } else {
                        pageController = nil
                    }
                }
        }
        if let pageController {
            if let webtoonReader = reader as? ReaderWebtoonViewController {
                webtoonReader.stopAutoScroll()
            }
            reader?.remove()
            pageController.delegate = self
            #if SUMI
            if let paged = pageController as? ReaderPagedViewController {
                paged.sumiOpeningIndex = sumiOpeningIndex
                paged.sumiSelectIndexChapter = { [weak self] chapter in self?.sumiSelectIndexChapter(chapter) }
            }
            #endif
            reader = pageController
            #if SUMI
            pageController.view.frame = view.bounds
            pageController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            #endif
            add(child: pageController, below: descriptionButtonController.view)
        }
        reader?.readingMode = readingMode
        #if SUMI
        sumiUpdateAccessibilityChildren()
        #endif
        configureDictionaryOverlayInteractionMode()
        configureDictionaryOverlayTapHandler()
        updateAutoScrollButton()
        disableSwipeGestures()
        updateTextThemeOverride()
    }

    func updateTextThemeOverride() {
        let theme = ReaderTextTheme.getCurrent()
        let isTextReader = reader is ReaderTextViewController || reader is ReaderPagedTextViewController
        let styleOverride: UIUserInterfaceStyle = isTextReader ? ReaderTextTheme.getInterfaceStyleOverride() : .unspecified
        navigationController?.overrideUserInterfaceStyle = styleOverride
        // presented sheets don't inherit the override
        presentedViewController?.overrideUserInterfaceStyle = styleOverride
        let themed = isTextReader && (theme != .default || styleOverride != .unspecified)

        // the bar appearance objects don't follow the trait override,
        // so the theme colors are written into them directly
        let backgroundColor = ReaderTextTheme.getCurrentBackground()
        let textColor = ReaderTextTheme.getCurrentText()
        let titleColor = themed ? textColor : nil
        if let navigationBar = navigationController?.navigationBar {
            func applyTheme(_ appearance: UINavigationBarAppearance) {
                if themed {
                    if #available(iOS 26.0, *), reader is ReaderTextViewController {
                        // text scrolls under the bar, so keep it transparent
                        appearance.configureWithTransparentBackground()
                    } else {
                        // nothing extends under the bar, so match the page color
                        appearance.backgroundEffect = nil
                        appearance.backgroundColor = backgroundColor
                        appearance.shadowColor = .clear
                    }
                    appearance.titleTextAttributes[.foregroundColor] = textColor
                } else {
                    appearance.configureWithDefaultBackground()
                    appearance.titleTextAttributes.removeValue(forKey: .foregroundColor)
                }
            }
            let standard = navigationBar.standardAppearance
            applyTheme(standard)
            navigationBar.standardAppearance = standard
            if let compact = navigationBar.compactAppearance {
                applyTheme(compact)
                navigationBar.compactAppearance = compact
            }
            if let scrollEdge = navigationBar.scrollEdgeAppearance {
                applyTheme(scrollEdge)
                navigationBar.scrollEdgeAppearance = scrollEdge
            }
        }
        // the two-line title view (volume + chapter) uses plain labels instead
        if let stackView = navigationItem.titleView as? UIStackView {
            let labels = stackView.arrangedSubviews.compactMap { $0 as? UILabel }
            if labels.count == 2 {
                labels[0].textColor = titleColor?.withAlphaComponent(0.6) ?? .secondaryLabel
                labels[1].textColor = titleColor ?? .label
            }
        }
    }
}

// MARK: - Auto Scroll
extension ReaderViewController {
    @objc private func toggleAutoScroll() {
        guard let webtoonReader = reader as? ReaderWebtoonViewController else { return }
        webtoonReader.toggleAutoScroll()
    }

    private func updateAutoScrollButton() {
        #if SUMI
        autoScrollButton.isHidden = true
        return
        #else
        let webtoonReader = reader as? ReaderWebtoonViewController
        let visible = webtoonReader != nil && UserDefaults.standard.bool(forKey: "Reader.autoScroll")

        if !visible {
            webtoonReader?.stopAutoScroll()
        }

        webtoonReader?.onAutoScrollStateChange = { [weak self] _ in
            self?.updateAutoScrollButtonIcon()
        }
        webtoonReader?.onContentScrollingChange = { [weak self] isScrolling in
            self?.setAutoScrollButtonDimmed(isScrolling)
        }

        autoScrollButton.isHidden = !visible
        updateAutoScrollButtonPosition(visible: visible)
        updateAutoScrollButtonIcon()
        #endif
    }

    private func updateAutoScrollButtonPosition(
        visible: Bool,
        animated: Bool = false
    ) {
        let position = AppSettings.reader.autoScrollPosition.get()
        let isRightAligned = position == .right

        let applyPosition = {
            self.autoScrollButtonLeadingConstraint.isActive = !isRightAligned
            self.autoScrollButtonTrailingConstraint.isActive = isRightAligned

            // when auto scroll button is on the right, the description button needs to be shifted to the left of it
            self.descriptionTrailingConstraint.isActive = !visible || !isRightAligned
            self.descriptionTrailingToAutoScrollConstraint.isActive = visible && isRightAligned
        }

        guard animated else {
            applyPosition()
            return
        }

        view.layoutIfNeeded()
        applyPosition()

        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut]
        ) {
            self.view.layoutIfNeeded()
        }
    }

    private func updateAutoScrollButtonIcon() {
        let isAutoScrolling = (reader as? ReaderWebtoonViewController)?.isAutoScrolling == true
        autoScrollButton.configuration?.image = UIImage(systemName: isAutoScrolling ? "pause.fill" : "play.fill")
    }

    @objc private func autoScrollButtonTouchDown() {
        isInteractingWithAutoScrollButton = true
        setAutoScrollButtonDimmed(false)
    }

    @objc private func autoScrollButtonTouchEnded() {
        isInteractingWithAutoScrollButton = false
        let isScrolling = (reader as? ReaderWebtoonViewController)?.isContentScrolling ?? false
        setAutoScrollButtonDimmed(isScrolling)
    }

    private func setAutoScrollButtonDimmed(_ dimmed: Bool) {
        let alpha: CGFloat = dimmed && !isInteractingWithAutoScrollButton ? 0.5 : 1

        guard autoScrollButton.alpha != alpha else { return }

        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]
        ) {
            self.autoScrollButton.alpha = alpha
        }
    }
}

// MARK: - Reader Holding Delegate
extension ReaderViewController: @MainActor ReaderHoldingDelegate {
    var barsHidden: Bool {
        #if SUMI
        !sumiControlsVisible
        #else
        statusBarHidden
        #endif
    }

    private func areDuplicates(_ a: AidokuRunner.Chapter, _ b: AidokuRunner.Chapter) -> Bool {
        a.chapterNumber == b.chapterNumber
            && a.volumeNumber == b.volumeNumber
            && (!(a.chapterNumber == nil && a.volumeNumber == nil) || a.title == b.title)
    }

    private func isValidScanlatorMatch(for next: AidokuRunner.Chapter, current: Set<String>) -> Bool {
        let nextScanlators = Set(next.scanlators ?? [])
        return current.isEmpty ? nextScanlators.isEmpty : !current.isDisjoint(with: nextScanlators)
    }

    private func findBestChapterMatch(from index: Int, step: Int) -> AidokuRunner.Chapter {
        let firstCandidate = chapterList[index]
        let currentScanlators = Set(chapter.scanlators ?? [])

        var i = index
        while i >= 0 && i < chapterList.count {
            let next = chapterList[i]
            guard areDuplicates(next, firstCandidate) else { break }

            let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: next.key)
            let isReadable = !next.locked || DownloadManager.shared.getDownloadStatus(for: identifier) == .finished

            if isReadable && isValidScanlatorMatch(for: next, current: currentScanlators) {
                return next
            }
            i += step
        }

        return firstCandidate
    }

    func getNextChapter() -> AidokuRunner.Chapter? {
        guard
            var index = chapterList.firstIndex(where: { $0.key == chapter.key })
        else {
            return nil
        }

        let skipDuplicates = UserDefaults.standard.bool(forKey: "Reader.skipDuplicateChapters")
        let markDuplicates = UserDefaults.standard.bool(forKey: "Reader.markDuplicateChapters")

        index -= 1
        var nextChapterInList: AidokuRunner.Chapter?

        while index >= 0 {
            let new = chapterList[index]
            let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: new.key)

            let readable = !new.locked
                || DownloadManager.shared.getDownloadStatus(for: identifier) == .finished

            if readable {
                let isDuplicate = areDuplicates(new, chapter)

                if nextChapterInList == nil {
                    nextChapterInList = new
                }
                if markDuplicates && isDuplicate {
                    chaptersToMark.append(new)
                }
                if !isDuplicate {
                    return skipDuplicates ? findBestChapterMatch(from: index, step: -1) : nextChapterInList
                } else if !skipDuplicates && !markDuplicates {
                    return new
                }
            }
            index -= 1
        }
        return nil
    }

    func getPreviousChapter() -> AidokuRunner.Chapter? {
        guard
            var index = chapterList.firstIndex(where: { $0.key == chapter.key })
        else {
            return nil
        }
        // find previous non-duplicate chapter
        let markDuplicates = UserDefaults.standard.bool(forKey: "Reader.markDuplicateChapters")

        index += 1
        while index < chapterList.count {
            let new = chapterList[index]
            let identifier = ChapterIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: new.key)

            let readable = !new.locked
                || DownloadManager.shared.getDownloadStatus(for: identifier) == .finished

            if readable {
                let isDuplicate = areDuplicates(new, chapter)
                if !isDuplicate {
                    return findBestChapterMatch(from: index, step: 1)
                }
                if markDuplicates {
                    chaptersToMark.append(new)
                }
            }
            index += 1
        }
        return nil
    }

    func setChapter(_ chapter: AidokuRunner.Chapter) {
        guard chapter != self.chapter else { return }

        #if SUMI
        sumiQueueReadPositionSave()
        sessionReadPages = []
        sessionStartDate = Date.now
        sessionLastInteraction = nil
        #else
        // Store current history data before the new chapter loads.
        let currentPage = currentPage
        let totalPages = toolbarView.totalPages
        let oldChapter = self.chapter
        Task {
            await updateReadPosition(currentPage: currentPage, totalPages: totalPages, chapter: oldChapter)
            sessionReadPages = [self.currentPage]
            sessionStartDate = Date.now
            sessionLastInteraction = nil
        }
        #endif

        self.chapter = chapter
        #if SUMI
        sumiHasPresentedActualPage = false
        #endif
        self.chaptersToMark = [chapter]
        configureBarToggleTapGestures()
        configureDictionaryLookupGesture()
        configureDictionaryOverlayInteractionMode()
        loadNavbarTitle()
        #if SUMI
        sumiUpdateReaderControls()
        #endif
    }

    func setCurrentPage(_ page: Int, position: Double? = nil) {
        setCurrentPages(page...page, position: position)
    }

    func setCurrentPages(_ pages: ClosedRange<Int>) {
        setCurrentPages(pages, position: nil)
    }

    private func setCurrentPages(_ pages: ClosedRange<Int>, position: Double? = nil) {
        guard let totalPages = toolbarView.totalPages else { return }

        updateDescriptionButton(pages: pages)
        updateAutoScrollButton()

        #if SUMI
        sumiLastVisiblePages = pages
        let recordVisiblePages = !sumiIsPreparingOpening
        #else
        let recordVisiblePages = true
        #endif
        if recordVisiblePages {
            sessionLastInteraction = Date.now
            for page in pages {
                guard page >= 1 && page <= totalPages else { continue }
                sessionReadPages.insert(page)
            }
        }

        let page = max(1, min(pages.lowerBound, totalPages))
        currentPage = page
        #if SUMI
        sumiHasPresentedActualPage = !sumiIsPreparingOpening
        let chapterLabel = chapter.chapterNumber.map { "Chapter \(String(format: "%g", Double($0)))" } ?? chapter.title ?? "Chapter"
        view.accessibilityValue = "\(chapterLabel), page \(page)"
        #if DEBUG
        if !sumiIsPreparingOpening, SumiGridPreviewFixtures.isEnabled && manga.sourceKey == SumiGridPreviewFixtures.sourceKey {
            SumiGridPreviewFixtures.recordProgress(manga: manga, chapter: chapter, page: page)
        }
        #endif
        if !sumiIsPreparingOpening, !sumiIsClosing {
            let selectedChapter = chapter
            let allChapters = sumiAllChapters
            Task { [weak self] in
                guard let self, !sumiIsClosing, chapter.key == selectedChapter.key else { return }
                await HonbakoEarlierChapterPrompt.consider(manga: manga, selected: selectedChapter,
                    chapters: allChapters, presenter: self, whileCurrent: { [weak self] in
                        guard let self else { return false }
                        return !sumiIsClosing && !sumiIsPreparingOpening && chapter.key == selectedChapter.key
                    })
            }
        }
        #endif
        currentPosition = position
        toolbarView.currentPage = page
        toolbarView.updateSliderPosition()
        #if SUMI
        sumiUpdateReaderControls()
        #endif
        // Mark as completed when reaching the last page
        // Exception: Don't mark for the pre-pagination placeholder (single text page before
        // ReaderPagedTextViewController has paginated it). Once paginated, even single-page
        // chapters should be marked as read.
        let isPrePaginationPlaceholder = totalPages == 1
            && self.pages.first?.isTextPage == true
            && !(reader is ReaderPagedTextViewController && (reader as? ReaderPagedTextViewController)?.hasPaginated == true)
        if pages.upperBound >= totalPages && !isPrePaginationPlaceholder {
            setCompleted()
        }
    }

    private func updateDescriptionButton(pages: ClosedRange<Int>) {
        #if SUMI
        descriptionButtonController.view.isHidden = true
        return
        #else
        let pageItems = pages.compactMap { self.pages[safe: $0 - 1]?.toNew() }
        if pageItems.contains(where: { $0.hasDescription }) {
            descriptionButtonController.rootView = ReaderPageDescriptionButtonView(
                source: source,
                pages: pageItems
            )
            descriptionButtonController.view.isHidden = false
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.descriptionButtonController.view.alpha = 1
            }
        } else {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.descriptionButtonController.view.alpha = 0
            } completion: { _ in
                self.descriptionButtonController.view.isHidden = true
            }
        }
        #endif
    }

    func setPages(_ pages: [Page]) {
        // If already in a text reader with text pages, just update toolbar - don't trigger any switches
        if
            reader is ReaderPagedTextViewController || reader is ReaderTextViewController,
            pages.allSatisfy({ $0.isTextPage }),
            pages.count > 1
        {
            self.pages = pages
            toolbarView.totalPages = pages.count
            activityIndicator.stopAnimating()
            return
        }
        self.pages = pages
        toolbarView.totalPages = pages.count
        activityIndicator.stopAnimating()
        #if SUMI
        sumiUpdateReaderControls()
        #endif
        if pages.isEmpty {
            // no pages, show error
            showLoadFailAlert()
        } else if pages.count == 1 && pages[0].isTextPage {
            // single text page, should switch to text reader
            if !(reader is ReaderPagedTextViewController) && !(reader is ReaderTextViewController) {
                setReader(.text)
                setChapter(chapter)
                loadCurrentChapter()
            } else {
            }
        } else if reader is ReaderPagedTextViewController && pages.allSatisfy({ $0.isTextPage }) {
            // Already in paginated text reader with multiple text pages (from pagination)
            // Don't switch away - this is our internal page count update
            // Just update the toolbar, don't reload
        } else {
            // otherwise, make sure we're not in the text reader
            if reader is ReaderTextViewController || reader is ReaderPagedTextViewController {
                switch readingMode {
                    case .ltr, .rtl, .vertical:
                        setReader(.paged)
                    case .webtoon, .continuous:
                        setReader(.scroll)
                }
                setChapter(chapter)
                loadCurrentChapter()
            }
        }
    }

    func displayPage(_ page: Int) {
        toolbarView.displayPage(page)
    }

    func setSliderOffset(_ offset: CGFloat) {
        toolbarView.sliderView.currentValue = offset
    }

    func setCompleted() {
        #if SUMI
        guard !sumiIsPreparingOpening else { return }
        #endif
        guard !AppSettings.general.incognitoMode.get() else { return }

        Task { [chaptersToMark] in
            await HistoryManager.shared.addHistory(
                mangaId: manga.identifier,
                chapters: chaptersToMark
            )
        }

        if AppSettings.downloads.deleteDownloadAfterReading.get() {
            chaptersToRemoveDownload.append(chapter)
        }
    }

    private func configureBarToggleTapGestures() {
        if let barToggleTapGesture {
            view.removeGestureRecognizer(barToggleTapGesture)
        }
        if let barToggleSecondaryTapGesture {
            view.removeGestureRecognizer(barToggleSecondaryTapGesture)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.delegate = self
        let singleTapLookupEnabled = isDictionarySingleTapLookupActiveForCurrentChapter
        configureNavigationBarDismissTapGesture(enabled: singleTapLookupEnabled)

        if !singleTapLookupEnabled, !UserDefaults.standard.bool(forKey: "Reader.disableDoubleTap") {
            let doubleTap = UITapGestureRecognizer(
                target: self,
                action: nil
            )
            doubleTap.numberOfTapsRequired = 2
            doubleTap.delegate = self
            view.addGestureRecognizer(doubleTap)
            tap.require(toFail: doubleTap)
            barToggleSecondaryTapGesture = doubleTap
        } else {
            barToggleSecondaryTapGesture = nil
        }

        view.addGestureRecognizer(tap)
        barToggleTapGesture = tap
    }

    private func configureNavigationBarDismissTapGesture(enabled: Bool) {
        guard let navigationBar = navigationController?.navigationBar else { return }

        if barDismissNavigationBarTapGesture == nil {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleNavigationBarTapToDismissBars(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            navigationBar.addGestureRecognizer(tap)
            barDismissNavigationBarTapGesture = tap
        }
        barDismissNavigationBarTapGesture?.isEnabled = enabled
    }

    @objc private func handleNavigationBarTapToDismissBars(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .ended else { return }
        guard isDictionarySingleTapLookupActiveForCurrentChapter else { return }
        hideBars()
    }

    private func configureDictionaryLookupGesture() {
        if let gesture = dictionaryLongPressGesture {
            view.removeGestureRecognizer(gesture)
            dictionaryLongPressGesture = nil
        }
        clearDictionarySelectionHighlight()
        if #available(iOS 18.0, *) {
            dictionaryLongPressSelection = nil
        }

        guard
            isDictionaryLongPressLookupActiveForCurrentChapter,
            !AppSettings.dictionary.textOverlayMode.get()
        else {
            return
        }

        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleDictionaryLongPress(_:)))
        gesture.minimumPressDuration = 0.25
        gesture.allowableMovement = 60
        gesture.cancelsTouchesInView = false
        view.addGestureRecognizer(gesture)
        dictionaryLongPressGesture = gesture
    }

    @objc private func handleDictionaryLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        guard
            #available(iOS 18.0, *),
            isDictionaryLongPressLookupActiveForCurrentChapter,
            !AppSettings.dictionary.textOverlayMode.get(),
            !dictionaryCoordinator.isPopupVisible,
            LookupEngine.shared.isReady
        else {
            return
        }

        let point = gestureRecognizer.location(in: view)
        switch gestureRecognizer.state {
            case .began, .changed:
                guard
                    let reader = reader as? ReaderDictionaryReader,
                    let result = reader.recognizedText(at: point)
                else {
                    dictionaryLongPressSelection = nil
                    clearDictionarySelectionHighlight()
                    return
                }
                dictionaryLongPressSelection = result
                updateDictionarySelectionHighlight(text: result.text, charRects: result.charRects)

            case .ended:
                defer {
                    dictionaryLongPressSelection = nil
                    clearDictionarySelectionHighlight()
                }
                var selection = dictionaryLongPressSelection
                if selection == nil, let reader = reader as? ReaderDictionaryReader {
                    selection = reader.recognizedText(at: point)
                }
                if let selection {
                    _ = dictionaryCoordinator.performLookup(
                        text: selection.text,
                        contextText: selection.fullText,
                        anchorRect: selection.charRect,
                        charRects: selection.charRects,
                        page: currentPage
                    )
                }

            default:
                dictionaryLongPressSelection = nil
                clearDictionarySelectionHighlight()
        }
    }

    @available(iOS 18.0, *)
    private func updateDictionarySelectionHighlight(text: String, charRects: [CGRect]) {
        dictionaryCoordinator.updateSelectionHighlight(text: text, charRects: charRects)
    }

    private func clearDictionarySelectionHighlight() {
        if #available(iOS 18.0, *) {
            dictionaryCoordinator.clearSelectionHighlight()
        }
    }
}

// MARK: - Tap Zones
extension ReaderViewController {
    private enum ReaderControlTapZoneConstants {
        static let minimumTapZoneHeight: CGFloat = 44
    }

    func updateTapZone() {
        let enabledTapZone = UserDefaults.standard.string(forKey: "Reader.tapZones")
        let tapZone: TapZone? = switch enabledTapZone {
            case "auto": switch reader {
                case is ReaderPagedViewController: .leftRight
                case is ReaderWebtoonViewController: .lShaped
                case is ReaderTextViewController: .lShaped
                case is ReaderPagedTextViewController: .leftRight  // Kindle-style tap zones
                default: .leftRight
            }
            case "left-right": .leftRight
            case "l-shaped": .lShaped
            case "kindle": .kindle
            case "edge": .edge
            default: nil
        }
        self.tapZone = tapZone
    }

    @objc func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        #if SUMI
        // A page tap always reveals the reader tools; swipes turn the book.
        sumiHandlePageTap(at: gestureRecognizer.location(in: view))
        return
        #else
        let point = gestureRecognizer.location(in: view)
        let overlayModeEnabled = AppSettings.dictionary.textOverlayMode.get()
        let singleTapLookupEnabled = isDictionarySingleTapLookupActiveForCurrentChapter
        let singleTapOCRLookupEnabled = singleTapLookupEnabled && !overlayModeEnabled

        // dismiss dictionary popup if visible
        if #available(iOS 18.0, *), dictionaryCoordinator.isPopupVisible {
            dictionaryCoordinator.dismissAllPopups()
            return
        }

        // dismiss text overlay box if visible
        if
            #available(iOS 18.0, *),
            overlayModeEnabled,
            let reader = reader as? ReaderDictionaryReader,
            reader.dismissActiveDictionaryOverlay()
        {
            return
        }

        // toggle bars when tapping safe areas
        if singleTapLookupEnabled, isReaderControlToggleTapZone(point) {
            toggleBarVisibility()
            return
        }

        // check for dictionary lookup
        if
            #available(iOS 18.0, *),
            singleTapOCRLookupEnabled,
            let reader = reader as? ReaderDictionaryReader,
            LookupEngine.shared.isReady
        {
            if let result = reader.recognizedText(at: point) {
                if dictionaryCoordinator.performLookup(
                    text: result.text,
                    contextText: result.fullText,
                    anchorRect: result.charRect,
                    charRects: result.charRects,
                    page: currentPage
                ).openedPopup {
                    return
                }
            }
        }

        guard let reader, let tapZone else {
            toggleBarVisibility()
            return
        }

        let relativePoint = CGPoint(
            x: point.x / view.bounds.width,
            y: point.y / view.bounds.height
        )

        let type = tapZone.regions
            .first { $0.bounds.contains(relativePoint) }
            .map(\.type)

        if let type {
            // hide the bars when tapping regardless
            if let navigationController, navigationController.navigationBar.alpha > 0 {
                hideBars()
            }
            // handle page moving
            if UserDefaults.standard.bool(forKey: "Reader.invertTapZones") {
                switch type {
                    case .left: reader.moveRight()
                    case .right: reader.moveLeft()
                }
            } else {
                switch type {
                    case .left: reader.moveLeft()
                    case .right: reader.moveRight()
                }
            }
        } else {
            toggleBarVisibility()
        }
        #endif
    }

    private func isReaderControlToggleTapZone(_ point: CGPoint) -> Bool {
        let topZoneHeight = readerControlTopTapZoneHeight
        if point.y <= topZoneHeight {
            return true
        }
        let bottomZoneMinY = view.bounds.height - readerControlBottomTapZoneHeight
        return point.y >= bottomZoneMinY
    }

    private var readerControlTopTapZoneHeight: CGFloat {
        view.safeAreaInsets.top + ReaderControlTapZoneConstants.minimumTapZoneHeight
    }

    private var readerControlBottomTapZoneHeight: CGFloat {
        view.safeAreaInsets.bottom + ReaderControlTapZoneConstants.minimumTapZoneHeight
    }
}

// MARK: - Apple Pencil Squeeze
extension ReaderViewController: UIPencilInteractionDelegate {
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        // if pencil squeezing is disabled globally, ignore interaction (hig)
        guard UIPencilInteraction.preferredSqueezeAction != .ignore else { return }

        switch squeeze.phase {
            case .began:
                squeezeStartTime = Date()
                longSqueezeTimer = Timer.scheduledTimer(
                    withTimeInterval: longSqueezeThreshold,
                    repeats: false
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.longSqueezeTimer = nil
                        self?.openChapterList()
                    }
                }
            case .ended:
                guard let startTime = squeezeStartTime else { return }
                let duration = Date().timeIntervalSince(startTime)
                squeezeStartTime = nil
                longSqueezeTimer?.invalidate()
                longSqueezeTimer = nil

                if duration >= longSqueezeThreshold {
                    // long squeeze: chapter selector
                    squeezeTimer?.invalidate()
                    squeezeTimer = nil
                    return
                } else {
                    if let timer = squeezeTimer {
                        // double squeeze: previous page
                        timer.invalidate()
                        squeezeTimer = nil
                        previousPage()
                    } else {
                        // single squeeze: next page
                        squeezeTimer = Timer.scheduledTimer(
                            withTimeInterval: doubleSqueezeInterval,
                            repeats: false
                        ) { [weak self] _ in
                            Task { @MainActor in
                                self?.squeezeTimer = nil
                                self?.nextPage()
                            }
                        }
                    }
                }
            default:
                break
        }

    }

    private func nextPage() {
        switch readingMode {
            case .rtl: reader?.moveLeft()
            default: reader?.moveRight()
        }
    }

    private func previousPage() {
        switch readingMode {
            case .rtl: reader?.moveRight()
            default: reader?.moveLeft()
        }
    }
}

extension ReaderViewController {
    private func configureDictionaryOverlayInteractionMode() {
        guard #available(iOS 18.0, *), let reader = reader as? ReaderDictionaryReader else { return }

        let mode: DictionaryOverlayInteractionMode
        if !AppSettings.dictionary.textOverlayMode.get() {
            mode = .none
        } else if isDictionarySingleTapLookupActiveForCurrentChapter {
            mode = .singleTap
        } else if isDictionaryLongPressLookupActiveForCurrentChapter {
            mode = .longPress
        } else {
            mode = .none
        }

        reader.setDictionaryOverlayInteractionMode(mode)
    }

    private func configureDictionaryOverlayTapHandler() {
        guard #available(iOS 18.0, *), let reader = reader as? ReaderDictionaryReader else { return }
        reader.setDictionaryOverlayTapHandler { [weak self] text, contextText, rect, charRects in
            guard let self, AppSettings.dictionary.textOverlayMode.get() else { return }
            _ = dictionaryCoordinator.performLookup(
                text: text,
                contextText: contextText,
                anchorRect: rect,
                charRects: charRects,
                page: currentPage
            )
        }
    }
}

// MARK: - Bar Visibility
extension ReaderViewController {
    @objc func toggleBarVisibility() {
        #if SUMI
        if !sumiControlsVisible { showBars() }
        else { hideBars() }
        return
        #else
        guard let navigationController else { return }
        if !navigationController.navigationBar.isHidden {
            hideBars()
        } else {
            showBars()
        }
        #endif
    }

    func showBars() {
        #if SUMI
        guard !sumiIsPreparingOpening else { return }
        let appearing = !sumiControlsVisible
        sumiControlsVisible = true
        sumiSetStatusBarHidden(false)
        sumiConfigureNativeControls()
        sumiScrubber.isHidden = false
        sumiUpdateReaderControls()
        sumiLayoutReaderControls()
        sumiUpdateAccessibilityChildren()
        if sumiReaderToolbar.superview === view { view.bringSubviewToFront(sumiReaderToolbar) }
        view.bringSubviewToFront(sumiReaderTitle)
        sumiReaderToolbar.setVisible(true, animated: appearing && !UIAccessibility.isReduceMotionEnabled)
        sumiReaderTitle.setVisible(true, animated: appearing && !UIAccessibility.isReduceMotionEnabled)
        NotificationCenter.default.post(name: .readerShowingBars, object: nil)
        return
        #else
        guard let navigationController else { return }

        if #available(iOS 27.0, *) {
            navigationController.navigationBar.isHidden = true
            navigationController.isNavigationBarHidden = false
        }

        UIView.animate(withDuration: CATransaction.animationDuration()) {
            self.statusBarHidden = false
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        } completion: { _ in
            NotificationCenter.default.post(name: .readerShowingBars, object: nil)

            UIView.setAnimationsEnabled(false)
            if #available(iOS 26.0, *) {
                if navigationController.isToolbarHidden {
                    (navigationController.value(forKey: "_floatingBarContainerView") as? UIView)?.alpha = 0
                    navigationController.isToolbarHidden = false
                }
            } else {
                if navigationController.toolbar.isHidden {
                    navigationController.toolbar.alpha = 0
                    navigationController.toolbar.isHidden = false
                }
            }
            navigationController.navigationBar.isHidden = false
            UIView.setAnimationsEnabled(true)
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                navigationController.navigationBar.alpha = 1
                navigationController.toolbar.alpha = 1
                if #available(iOS 26.0, *) {
                    (navigationController.value(forKey: "_floatingBarContainerView") as? UIView)?.alpha = 1
                }
                self.node.backgroundColor = if AppSettings.appearance.useSystemAppearance.get() {
                    .systemBackground
                } else {
                    if AppSettings.appearance.appearance.get() == 0 {
                        .white
                    } else {
                        .black
                    }
                }
                self.node.layoutIfNeeded()
            }
        }
        #endif
    }

    func hideBars() {
        #if SUMI
        sumiHideControlsForPageTurn()
        sumiScrubber.suspendImages()
        return
        #else
        guard let navigationController else { return }

        UIView.animate(withDuration: CATransaction.animationDuration()) {
            self.statusBarHidden = true
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        } completion: { _ in
            NotificationCenter.default.post(name: .readerHidingBars, object: nil)

            UIView.animate(withDuration: CATransaction.animationDuration()) {
                navigationController.navigationBar.alpha = 0
                navigationController.toolbar.alpha = 0

                if #available(iOS 26.0, *) {
                    (navigationController.value(forKey: "_floatingBarContainerView") as? UIView)?.alpha = 0
                }

                self.node.backgroundColor = switch UserDefaults.standard.string(forKey: "Reader.backgroundColor") {
                    case "system":
                        .systemBackground
                    case "white":
                        .white
                    default:
                        .black
                }
                self.node.layoutIfNeeded()
            } completion: { _ in
                if #available(iOS 27.0, *) {
                    navigationController.isNavigationBarHidden = true
                } else {
                    navigationController.navigationBar.isHidden = true
                }
                if #available(iOS 26.0, *) {
                    navigationController.isToolbarHidden = true
                } else {
                    navigationController.toolbar.isHidden = true
                }
            }
        }
        #endif
    }

}

// MARK: - UIGestureRecognizerDelegate
extension ReaderViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: pan.view)
        return velocity.y > velocity.x && (abs(velocity.x) < 40 || abs(velocity.y) > abs(velocity.x) * 3)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard
            gestureRecognizer === barDismissNavigationBarTapGesture
                || gestureRecognizer === barToggleTapGesture
                || gestureRecognizer === barToggleSecondaryTapGesture
        else {
            return true
        }

        var view: UIView? = touch.view
        while let currentView = view {
            #if SUMI
            if currentView is UITableViewCell { return false }
            #endif
            if currentView is UIControl {
                return false
            }
            view = currentView.superview
        }
        return true
    }
}

// MARK: - Keyboard Shortcuts
extension ReaderViewController {
    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        #if SUMI
        // Sheets and text fields retain their own editing and dismissal keys.
        guard presentedViewController == nil, !sumiIsPreparingOpening, !sumiIsClosing else { return nil }
        return [
            UIKeyCommand(title: "Turn page left", action: #selector(moveLeft), input: UIKeyCommand.inputLeftArrow),
            UIKeyCommand(title: "Turn page right", action: #selector(moveRight), input: UIKeyCommand.inputRightArrow),
            UIKeyCommand(title: "Continue reading", action: #selector(sumiAdvance), input: " "),
            UIKeyCommand(title: "Previous page", action: #selector(sumiRetreat), input: " ", modifierFlags: .shift),
            UIKeyCommand(title: "Scroll forward", action: #selector(sumiAdvance), input: UIKeyCommand.inputDownArrow),
            UIKeyCommand(title: "Scroll back", action: #selector(sumiRetreat), input: UIKeyCommand.inputUpArrow),
            UIKeyCommand(title: "Chapters and language", action: #selector(openChapterList), input: "l", modifierFlags: .command),
            UIKeyCommand(title: "Show controls", action: #selector(toggleBarVisibility), input: "i", modifierFlags: .command),
            UIKeyCommand(title: "Close book", action: #selector(close), input: "w", modifierFlags: .command),
            UIKeyCommand(title: "Close book", action: #selector(close), input: UIKeyCommand.inputEscape)
        ]
        #else
        let commands = [
            UIKeyCommand(
                title: NSLocalizedString("TURN_PAGE_LEFT"),
                action: #selector(moveLeft),
                input: UIKeyCommand.inputLeftArrow
            ),
            UIKeyCommand(
                title: NSLocalizedString("TURN_PAGE_RIGHT"),
                action: #selector(moveRight),
                input: UIKeyCommand.inputRightArrow
            ),
            UIKeyCommand(
                title: NSLocalizedString("TOGGLE_PAGE_OFFSET"),
                action: #selector(toggleOffset),
                input: "o"
            ),
            UIKeyCommand(
                title: NSLocalizedString("CHAPTER_FORWARD"),
                action: #selector(nextChapter),
                input: ","
            ),
            UIKeyCommand(
                title: NSLocalizedString("CHAPTER_BACKWARD"),
                action: #selector(previousChapter),
                input: "."
            ),
            UIKeyCommand(
                title: NSLocalizedString("OPEN_CHAPTER_LIST"),
                action: #selector(openChapterList),
                input: "\t"
            ),
            UIKeyCommand(
                title: NSLocalizedString("TOGGLE_BARS"),
                action: #selector(toggleBarVisibility),
                input: " "
            ),
            UIKeyCommand(
                title: NSLocalizedString("CLOSE_READER"),
                action: #selector(close),
                input: UIKeyCommand.inputEscape
            )
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands
        #endif
    }

    #if SUMI
    @objc private func sumiAdvance() {
        if readingMode == .rtl { reader?.moveLeft() }
        else { reader?.moveRight() }
    }

    @objc private func sumiRetreat() {
        if readingMode == .rtl { reader?.moveRight() }
        else { reader?.moveLeft() }
    }
    #endif

    @objc func moveLeft() {
        reader?.moveLeft()
    }

    @objc func moveRight() {
        reader?.moveRight()
    }

    @objc func toggleOffset() {
        reader?.toggleOffset()
    }

    @objc func nextChapter() {
        if let nextChapter = getNextChapter() {
            reader?.setChapter(nextChapter, startPage: 1)
            setChapter(nextChapter)
        }
    }

    @objc func previousChapter() {
        if let previousChaoter = getPreviousChapter() {
            reader?.setChapter(previousChaoter, startPage: 1)
            setChapter(previousChaoter)
        }
    }
}
