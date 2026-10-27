#if SUMI
import SwiftUI
import UIKit

/// Hosts the full-bleed collection and owns direct book presentation.
final class SumiGridViewController: UIViewController {
    private let store = SumiLibraryStore(tutorialInstaller: { await HonbakoTutorialManga.ensureInstalled() })
    private let discovery = SumiDiscoveryStore()
    private let opening = SumiGridOpeningState()
    private let search = SumiSearchPresentation()
    private let insertion = SumiLibraryInsertionState()
    private var openingTask: Task<Void, Never>?
    private var pendingHistorySave: Task<Void, Never>?
    private var loadingController: SumiReaderLoadingViewController?
    private var stagedReader: SumiDirectReaderController?
    #if DEBUG
    private let fixtures: SumiGridPreviewFixtures?
    #endif

    init(preview: Bool = false) {
        #if DEBUG
        fixtures = preview ? SumiGridPreviewFixtures() : nil
        #endif
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "Sumi.Grid.Screen"
        #if DEBUG
        let previewBooks = fixtures?.books
        #else
        let previewBooks: [SumiBook]? = nil
        #endif
        let host = UIHostingController(rootView: SumiMainView(
            store: store, discovery: discovery, opening: opening, search: search, insertion: insertion,
            previewBooks: previewBooks, openBook: openBook,
            dismissSearch: { [weak self] in self?.dismissSearch() },
            didAddBook: { [weak self] book, source in
                guard let self else { source?.finish(); return }
                await self.morphAddedBook(book, source: source)
            }
        ))
        host.view.backgroundColor = .systemBackground
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        guard let canvas = view else { return }
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: canvas.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: canvas.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !search.isPresented { becomeFirstResponder() }
    }

    override var keyCommands: [UIKeyCommand]? {
        guard presentedViewController == nil, loadingController == nil else { return nil }
        return [
            UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(revealSearch), discoverabilityTitle: "Search Manga"),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(dismissSearch), discoverabilityTitle: "Close Search")
        ]
    }

    @objc private func revealSearch() {
        guard presentedViewController == nil, loadingController == nil else { return }
        search.reveal()
    }

    @objc private func dismissSearch() {
        view.endEditing(true)
        search.dismiss()
        store.cancelSearch()
    }

    private func openBook(_ book: SumiBook, source: SumiBookTransitionSource?) {
        guard presentedViewController == nil, loadingController == nil, insertion.bookID == nil else { source?.finish(); return }
        search.suspendKeyboard()
        store.cancelSearch()
        view.endEditing(true)
        // Preserve a complete cover for the animation after loading finishes.
        let snapshot = (source?.view as? UIImageView)?.image
        let loading = SumiReaderLoadingViewController(book: book, snapshot: snapshot,
            canvasAspect: source?.closedPose == nil ? 0.68 : SumiGridBookPose.canvasAspect)
        loadingController = loading
        addChild(loading)
        loading.view.frame = view.bounds
        loading.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(loading.view)
        loading.didMove(toParent: self)
        loading.beginLoading(from: source?.view)
        opening.bookID = book.presentation.id
        loading.closeBook = { [weak self, weak loading] in
            guard let self, let loading, self.loadingController === loading else { return }
            self.openingTask?.cancel()
            self.openingTask = nil
            self.removeStagedReader()
            loading.returnToSource(frame: { source?.frame(in: loading.view) }) { [weak self, weak loading] in
                guard let self, self.loadingController === loading else { return }
                self.removeLoading()
                source?.finish()
            }
        }
        loading.retry = { [weak self, weak loading] in
            guard let loading else { return }
            self?.prepareReader(book: book, source: source, loading: loading)
        }
        prepareReader(book: book, source: source, loading: loading)
    }

    private func morphAddedBook(_ book: SumiBook, source: SumiBookTransitionSource?) async {
        defer { source?.finish() }
        guard search.isPresented, insertion.bookID == nil, presentedViewController == nil, loadingController == nil else { return }
        guard let source, let image = (source.view as? UIImageView)?.image,
              let origin = source.frame(in: view) else {
            dismissSearch()
            return
        }
        let cover = UIImageView(image: image)
        cover.frame = origin
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerCurve = .continuous
        cover.layer.cornerRadius = 8
        cover.isUserInteractionEnabled = false
        cover.isAccessibilityElement = true
        cover.accessibilityLabel = "Adding \(book.title) to Library"
        cover.accessibilityIdentifier = "Sumi.Search.AddingCover"
        view.addSubview(cover)
        insertion.begin(bookID: book.presentation.id)
        defer { insertion.finish(); cover.removeFromSuperview() }
        search.suspendKeyboard()
        view.endEditing(true)
        // Resolve the real saved cell after the keyboard and library insertion
        // have laid out. The search panel hides this scroll to the new slot.
        for _ in 0..<24 {
            view.layoutIfNeeded()
            if view.keyboardLayoutGuide.layoutFrame.height <= view.safeAreaInsets.bottom + 2 { break }
            if Task.isCancelled || !search.isPresented { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        var destination: CGRect?
        var previousDestination: CGRect?
        var stableDestinationFrames = 0
        for attempt in 0..<40 {
            if Task.isCancelled || !search.isPresented { return }
            view.layoutIfNeeded()
            if let frame = insertion.frame(in: view) {
                if frame == previousDestination { stableDestinationFrames += 1 }
                else { stableDestinationFrames = 0 }
                previousDestination = frame
                if stableDestinationFrames >= 2 { destination = frame; break }
            } else if attempt.isMultiple(of: 5) { insertion.requestScroll() }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard search.isPresented else { return }
        dismissSearch()
        await withCheckedContinuation { continuation in
            UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.18 : 0.55,
                           delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                if let destination, !UIAccessibility.isReduceMotionEnabled {
                    cover.frame = destination
                    cover.layer.cornerRadius = 0
                } else { cover.alpha = 0 }
            } completion: { _ in continuation.resume() }
        }
    }

    private func prepareReader(book: SumiBook, source: SumiBookTransitionSource?,
                               loading: SumiReaderLoadingViewController) {
        openingTask?.cancel()
        removeStagedReader()
        loading.showLoading()
        openingTask = Task { [weak self, weak loading] in
            guard let self else { return }
            await pendingHistorySave?.value
            guard !Task.isCancelled, let loading, loadingController === loading else { return }
            #if DEBUG
            if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--sumi-loading-delay=") }),
               let seconds = Double(argument.split(separator: "=").last ?? ""), seconds > 0 {
                try? await Task.sleep(for: .seconds(min(seconds, 10)))
            }
            #endif
            guard !Task.isCancelled else { return }
            let selection: SumiReaderOpening?
            #if DEBUG
            if let fixtures { selection = await fixtures.prepareReader(for: book) }
            else { selection = await store.prepareReader(book: book) }
            #else
            selection = await store.prepareReader(book: book)
            #endif
            guard !Task.isCancelled, loadingController === loading else { return }
            guard let selection else {
                loading.showError(store.errorMessage ?? "This manga couldn’t be opened. Try again.")
                return
            }
            let position = selection.selection
            let reader = ReaderViewController(source: position.source, manga: position.manga,
                                              chapter: position.chapter, startPage: position.startPage)
            reader.sumiIsPreparingOpening = true
            // Unread books open on real artwork. Chapters live in the reader sidebar.
            let presentation = SumiDirectReaderController(content: reader)
            stage(presentation)
            guard await reader.sumiWaitForOpening() else {
                guard !Task.isCancelled, loadingController === loading else { return }
                // Signed image URLs can expire before their short cache TTL.
                // Retrying a failed first page must request a fresh page list.
                if let source = position.source {
                    await SumiChapterPageListCache.shared.invalidate(.init(source: source,
                        manga: position.manga, chapter: position.chapter))
                }
                removeStagedReader()
                loading.showError("The reading page couldn’t be loaded. Try again.")
                return
            }
            guard !Task.isCancelled, loadingController === loading, stagedReader === presentation else { return }
            await loading.prepareOpening()
            guard !Task.isCancelled, loadingController === loading else { return }
            unstage(presentation)
            reader.view.accessibilityIdentifier = "Sumi.DirectReader"
            configureOpening(presentation, book: book, source: source, loading: loading)
            loading.view.isUserInteractionEnabled = false
            present(presentation, animated: true) { [weak self, weak presentation, weak reader] in
                self?.removeLoading()
                self?.openingTask = nil
                guard presentation?.presentingViewController != nil else { return }
                reader?.sumiDidOpenPreparedBook()
                if !AppSettings.general.incognitoMode.get() {
                    Task { await CoreDataManager.shared.setOpened(mangaId: book.id) }
                }
            }
        }
    }

    /// Give Texture and its page images a real viewport behind the grid while
    /// loading. It stays inaccessible until the ready book is presented.
    private func stage(_ controller: SumiDirectReaderController) {
        stagedReader = controller
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.accessibilityElementsHidden = true
        view.insertSubview(controller.view, at: 0)
        controller.didMove(toParent: self)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }

    private func unstage(_ controller: SumiDirectReaderController) {
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        controller.view.accessibilityElementsHidden = false
        if stagedReader === controller { stagedReader = nil }
    }

    private func removeStagedReader() {
        if let stagedReader { unstage(stagedReader) }
    }

    private func removeLoading() {
        if let loadingController {
            loadingController.stopHovering()
            loadingController.willMove(toParent: nil)
            loadingController.view.removeFromSuperview()
            loadingController.removeFromParent()
        }
        loadingController = nil
        opening.bookID = nil
        if presentedViewController == nil { becomeFirstResponder() }
    }

    private func configureOpening(_ presentation: SumiDirectReaderController, book: SumiBook,
                                  source: SumiBookTransitionSource?, loading: SumiReaderLoadingViewController) {
        // Retain the search row and its scroll geometry behind the opaque
        // reader. Reattaching a full-screen host used to autofocus its search
        // field and move the return destination while the book was closing.
        presentation.modalPresentationStyle = .overFullScreen
        presentation.view.backgroundColor = SumiPaperSurface.backgroundColor
        presentation.view.accessibilityViewIsModal = true
        let reader = presentation.readerViewController
        let transition = SumiBookTransition(coverImage: source?.coverArtwork ?? loading.coverSnapshot(),
            closedPose: source?.closedPose,
            liftedFrame: loading.zoomSourceView.convert(loading.zoomSourceView.bounds, to: view),
            liftedViewport: view.bounds.size,
            sourceFrameProvider: { [weak self, weak loading] container in
                if let loading, self?.loadingController === loading {
                    return loading.zoomSourceView.convert(loading.zoomSourceView.bounds, to: container)
                }
                return source?.frame(in: container)
            }, gridSourceFrameProvider: { container in
                source?.frame(in: container)
            }, readerSurface: { [weak reader] in
            reader?.reader?.view
        }, paired: { [weak reader] in
            (reader?.reader as? ReaderPagedViewController)?.sumiUsesSpreads ?? false
        }) { [weak self, weak loading] in
            if let loading, self?.loadingController === loading { return loading.zoomSourceView }
            return source?.view
        }
        presentation.bookTransition = transition
        transition.chromeTransition = { [weak reader] transitioning in reader?.sumiSetBookTransitioning(transitioning) }
        transition.sourceVisibility = { [weak self, weak loading] hidden in
            guard let self else { return }
            if let loading, loadingController === loading { loading.zoomSourceView.isHidden = hidden }
            else { opening.bookID = hidden ? book.presentation.id : nil }
        }
        transition.openingCancellationBegan = { [weak self, weak loading] in
            self?.openingTask?.cancel()
            loading?.view.isHidden = true
        }
        transition.openingCancelled = { [weak self, weak loading] in
            guard let self, self.loadingController === loading else { return }
            self.openingTask = nil
            self.removeLoading()
            source?.finish()
        }
        presentation.transitioningDelegate = transition
        transition.install(on: presentation)
        presentation.onBookDismissed = { [weak self, weak presentation] in
            if let reader = presentation?.readerViewController {
                self?.pendingHistorySave = reader.sumiPendingHistorySave
                #if DEBUG
                self?.fixtures?.readerDidClose(reader)
                #endif
            }
            source?.finish()
            // An over-full-screen reader keeps this controller attached, so
            // viewDidAppear is not called again to restore keyboard commands.
            self?.becomeFirstResponder()
            #if DEBUG
            if let self, SumiBookPinchDiagnostics.isEnabled {
                self.recordPinchReturn(source: source, checkpoint: "dismissal")
                Task { @MainActor [weak self] in
                    await Task.yield()
                    self?.recordPinchReturn(source: source, checkpoint: "nextTurn")
                    try? await Task.sleep(for: .milliseconds(350))
                    self?.recordPinchReturn(source: source, checkpoint: "settled")
                }
            }
            #endif
        }
    }

    #if DEBUG
    private func recordPinchReturn(source: SumiBookTransitionSource?, checkpoint: String) {
        guard SumiBookPinchDiagnostics.isEnabled else { return }
        let frame = source?.frame(in: view)
        let center = frame.map { CGPoint(x: $0.midX, y: $0.midY) }
            ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let windows: [[String: Any]] = (view.window?.windowScene?.windows ?? []).map { window in
            let point = view.convert(center, to: window)
            let hit = window.hitTest(point, with: nil)
            return ["class": SumiBookPinchDiagnostics.typeName(window), "level": window.windowLevel.rawValue,
                "hidden": window.isHidden, "enabled": window.isUserInteractionEnabled,
                "alpha": SumiBookPinchDiagnostics.number(window.alpha), "key": window.isKeyWindow,
                "root": SumiBookPinchDiagnostics.typeName(window.rootViewController),
                "rootPresented": SumiBookPinchDiagnostics.typeName(window.rootViewController?.presentedViewController),
                "frame": String(describing: window.frame), "pointX": point.x, "pointY": point.y,
                "hitAncestry": SumiBookPinchDiagnostics.ancestry(of: hit)]
        }
        SumiBookPinchDiagnostics.record("libraryReturn", ["checkpoint": checkpoint,
            "searchPresented": search.isPresented, "searchReveal": search.revealProgress,
            "openingBookID": opening.bookID ?? "nil", "insertingBookID": insertion.bookID ?? "nil",
            "loading": loadingController != nil, "presented": SumiBookPinchDiagnostics.typeName(presentedViewController),
            "sourceFrame": frame.map { String(describing: $0) } ?? "nil", "presenterAncestry": SumiBookPinchDiagnostics.ancestry(of: view),
            "windows": windows])
    }
    #endif
}
#endif
