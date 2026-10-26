#if SUMI
import SwiftUI
import UIKit

/// Hosts the full-bleed collection and owns direct book presentation.
final class SumiGridViewController: UIViewController {
    private let store = SumiLibraryStore()
    private let discovery = SumiDiscoveryStore()
    private let opening = SumiGridOpeningState()
    private let search = SumiSearchPresentation()
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
            store: store, discovery: discovery, opening: opening, search: search,
            previewBooks: previewBooks, openBook: openBook,
            dismissSearch: { [weak self] in self?.dismissSearch() }
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
        guard presentedViewController == nil, loadingController == nil else { source?.finish(); return }
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
    }

    private func configureOpening(_ presentation: SumiDirectReaderController, book: SumiBook,
                                  source: SumiBookTransitionSource?, loading: SumiReaderLoadingViewController) {
        presentation.modalPresentationStyle = .fullScreen
        presentation.view.backgroundColor = SumiPaperSurface.backgroundColor
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
        }
    }
}
#endif
