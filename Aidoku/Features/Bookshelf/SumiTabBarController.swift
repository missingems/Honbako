#if SUMI
import SwiftUI
import UIKit

final class SumiTabBarController: UITabBarController, UINavigationControllerDelegate {
    private let store = SumiLibraryStore()
    private let libraryVisibility = SumiLibraryVisibility()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let reading = UIHostingController(rootView: SumiReadingView(store: store, openBook: openBook, visibility: libraryVisibility, findBooks: { [weak self] in
            self?.selectedTab = self?.tabs.first { $0.identifier == "search" }
        }))
        reading.navigationItem.largeTitleDisplayMode = .never
        let readingNav = NavigationController(rootViewController: reading)
        readingNav.delegate = self
        readingNav.setNavigationBarHidden(true, animated: false)

        let search = SumiSearchViewController(store: store, openBook: openBook)
        let searchNav = NavigationController(rootViewController: search)
        searchNav.delegate = self
        searchNav.navigationBar.prefersLargeTitles = false

        let readingTab = UITab(title: "Reading", image: UIImage(systemName: "books.vertical"), identifier: "reading") { _ in readingNav }
        let searchTab = UITab(title: "Search", image: UIImage(systemName: "magnifyingglass"), identifier: "search") { _ in searchNav }
        for tab in [readingTab, searchTab] {
            tab.allowsHiding = false
            tab.preferredPlacement = .fixed
        }
        tabs = [readingTab, searchTab]
    }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        navigationController.setNavigationBarHidden(viewController is UIHostingController<SumiReadingView>, animated: animated)
    }

    private func openBook(_ book: SumiBook, source: SumiBookTransitionSource?) {
        guard let navigation = selectedViewController as? UINavigationController,
              navigation.presentedViewController == nil else { source?.finish(); return }
        navigation.topViewController?.view.endEditing(true)
        SumiBookPresentation.present(book, store: store, from: navigation, visibility: libraryVisibility, source: source)
    }
}
#endif
