#if SUMI
import SwiftUI
import UIKit

/// UIKit owns the system search field while SwiftUI shows only the books.
final class SumiSearchViewController: UIViewController, UISearchResultsUpdating, UISearchBarDelegate {
    private let store: SumiLibraryStore
    private let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    private let searchController = UISearchController(searchResultsController: nil)
    private var lastQuery: String?

    init(store: SumiLibraryStore, openBook: @escaping (SumiBook, SumiBookTransitionSource?) -> Void) {
        self.store = store
        self.openBook = openBook
        super.init(nibName: nil, bundle: nil)
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.searchController = searchController
        navigationItem.preferredSearchBarPlacement = .integrated
        navigationItem.searchBarPlacementAllowsToolbarIntegration = false
        navigationItem.backButtonTitle = "Search"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        definesPresentationContext = true
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.delegate = self
        searchController.searchBar.placeholder = "Search"
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.autocorrectionType = .no

        let host = UIHostingController(rootView: SumiSearchView(store: store, openBook: openBook, retry: { [weak self] in
            self?.runSearch(force: true)
        }))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        runSearch()
    }

    func updateSearchResults(for searchController: UISearchController) { runSearch() }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        runSearch()
        searchBar.resignFirstResponder()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        runSearch()
    }

    private func runSearch(force: Bool = false) {
        let query = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard force || query != lastQuery else { return }
        lastQuery = query
        store.search(query: query)
    }
}
#endif
