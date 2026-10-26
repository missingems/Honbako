#if SUMI
import SwiftUI

struct SumiSearchTabView: View {
    @ObservedObject var store: SumiLibraryStore
    @ObservedObject var opening: SumiGridOpeningState
    let previewBooks: [SumiBook]?
    let isSelected: Bool
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    @State private var query = ""
    @State private var searchPresented = false
    @FocusState private var searchFocused: Bool

    private var results: [SumiBook] {
        if let previewBooks {
            return query.isEmpty ? Array(previewBooks.prefix(20))
                : previewBooks.filter { $0.title.localizedStandardContains(query) }
        }
        return store.searchResults
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let count = max(2, Int((geometry.size.width - 24 + 12) / 154))
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: count), spacing: 16) {
                        ForEach(results) { book in
                            SumiGridCoverTile(book: book, openBook: openBook)
                                .opacity(opening.bookID == book.presentation.id ? 0 : 1)
                        }
                    }
                    .padding(12)
                    if store.isSearching { ProgressView().padding() }
                    if !store.isSearching, !query.isEmpty, results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("Sumi.Search.Results")
            }
            .background { Color.white.ignoresSafeArea() }
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, isPresented: $searchPresented,
                        placement: .navigationBarDrawer(displayMode: .always), prompt: "Search manga")
            .searchFocused($searchFocused)
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .toolbar {
                // iPad's search drawer replaces the tab strip without providing
                // the compact search controller's standard close affordance.
                if UIDevice.current.userInterfaceIdiom == .pad, searchPresented {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) {
                            searchFocused = false
                            searchPresented = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                    }
                }
            }
            .task(id: isSelected) {
                guard isSelected else { searchFocused = false; searchPresented = false; return }
                searchPresented = true
                await Task.yield()
                searchFocused = true
                if previewBooks == nil, query.isEmpty { store.search(query: "") }
            }
            .onChange(of: query) {
                guard previewBooks == nil else { return }
                store.search(query: query)
            }
        }
    }
}
#endif
