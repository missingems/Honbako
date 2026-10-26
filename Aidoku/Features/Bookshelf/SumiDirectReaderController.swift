#if SUMI
import UIKit

/// The system owns the adaptive reader bars; artwork extends underneath them.
final class SumiDirectReaderController: UINavigationController {
    private(set) var content: UIViewController
    var onBookDismissed: (() -> Void)?
    var readerViewController: ReaderViewController? { content as? ReaderViewController }
    var bookTransition: SumiBookTransition?

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

    func show(_ controller: UIViewController) {
        loadViewIfNeeded()
        content = controller
        setViewControllers([controller], animated: false)
        view.layoutIfNeeded()
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
        guard let action = onBookDismissed else { return }
        onBookDismissed = nil
        readerViewController?.sumiBookDidClose()
        action()
    }
}
#endif
