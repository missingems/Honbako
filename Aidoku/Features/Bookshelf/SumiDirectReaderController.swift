#if SUMI
import UIKit

/// The system owns the adaptive reader bars; artwork extends underneath them.
final class SumiDirectReaderController: UINavigationController {
    private(set) var content: UIViewController
    var onBookDismissed: (() -> Void)?
    var readerViewController: ReaderViewController? { content as? ReaderViewController }
    var bookTransition: SumiBookTransition?
    private var coverDisplaySession: HonbakoCoverDisplaySession?

    init(content: UIViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        setViewControllers([content], animated: false)
        setNavigationBarHidden(true, animated: false)
        setToolbarHidden(true, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var childForStatusBarHidden: UIViewController? { topViewController }
    override var childForStatusBarStyle: UIViewController? { topViewController }
    override var prefersStatusBarHidden: Bool { content.prefersStatusBarHidden }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        navigationBar.prefersLargeTitles = false
        navigationBar.isTranslucent = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        bookTransition?.prioritizeBackSwipe()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        bookTransition?.prioritizeBackSwipe()
        startCoverDisplayIfPresented()
    }

    @available(iOS 26.0, *)
    override func updateProperties() {
        super.updateProperties()
        coverDisplaySession?.updateAvailability()
    }

    func show(_ controller: UIViewController) {
        loadViewIfNeeded()
        content = controller
        setViewControllers([controller], animated: false)
        view.layoutIfNeeded()
        startCoverDisplayIfPresented()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if presentingViewController == nil { finishDismissal() }
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag) { [weak self] in
            if self?.presentingViewController == nil { self?.finishDismissal() }
            completion?()
        }
    }

    private func finishDismissal() {
        coverDisplaySession?.stop()
        coverDisplaySession = nil
        bookTransition?.uninstall()
        bookTransition = nil
        guard let action = onBookDismissed else { return }
        onBookDismissed = nil
        readerViewController?.sumiBookDidClose()
        action()
    }

    private func startCoverDisplayIfPresented() {
        // The hidden staging controller prepares pages before opening. Only a
        // genuinely presented reader should offer cover-display content.
        guard presentingViewController != nil, let reader = readerViewController else { return }
        let session = coverDisplaySession ?? HonbakoCoverDisplaySession()
        coverDisplaySession = session
        session.start(on: self, manga: reader.manga, source: reader.source)
    }
}
#endif
