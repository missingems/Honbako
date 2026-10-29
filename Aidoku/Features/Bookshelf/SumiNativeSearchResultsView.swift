#if SUMI
import AidokuRunner
import SwiftUI

struct SumiNativeSearchResultsView: View {
    @ObservedObject var store: SumiLibraryStore
    @ObservedObject var presentation: SumiSearchPresentation
    @ObservedObject var opening: SumiGridOpeningState
    @ObservedObject var insertion: SumiLibraryInsertionState
    let previewBooks: [SumiBook]?
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    let openSettings: () -> Void
    let didAddBook: (SumiBook, SumiBookTransitionSource?) async -> Void
    @State private var previewLibraryIDs: Set<MangaIdentifier> = []

    private var query: String { presentation.query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var books: [SumiBook] {
        if let previewBooks {
            return query.isEmpty ? Array(previewBooks.prefix(6)) : previewBooks.filter { $0.title.localizedStandardContains(query) }
        }
        let recent = store.recentlyRead.isEmpty ? store.library : store.recentlyRead
        return query.isEmpty ? Array(recent.prefix(6)) : store.searchResults
    }
    private var sections: [SumiSearchSourceSection] {
        if !query.isEmpty, previewBooks == nil { return store.searchSections }
        return SumiSearchSourceSection.grouping(books, sourceName: store.sourceName(for:))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.books) { book in
                            SumiSpotlightResultRow(book: book,
                                isLifted: opening.bookID == book.presentation.id || insertion.bookID == book.presentation.id,
                                isInLibrary: book.isInLibrary || previewLibraryIDs.contains(book.id),
                                editions: store.editions(for: book), sourceName: store.sourceName(for:),
                                openBook: openBook, addBook: { book, source in
                                    if previewBooks != nil { previewLibraryIDs.insert(book.id) }
                                    else {
                                        await store.add(book: book)
                                        guard store.library.contains(where: { $0.id == book.id }) else { source?.finish(); return }
                                    }
                                    await didAddBook(book, source)
                                }, showsDivider: book.id != section.books.last?.id)
                                .padding(.horizontal, 8)
                        }
                    } header: { SumiSearchSourceHeader(name: section.name, sourceKey: section.sourceKey) }
                }
                if store.isSearching, previewBooks == nil {
                    ProgressView().padding(24).accessibilityLabel("Searching")
                        .accessibilityIdentifier("Honbako.Search.Loading")
                } else if books.isEmpty {
                    if store.needsConnection, previewBooks == nil, !query.isEmpty {
                        ContentUnavailableView {
                            Label("Connect a Library", systemImage: "link")
                        } description: { Text("Add your files, a personal server, or a source to search.") }
                        actions: { Button("Settings", action: openSettings) }
                    } else if let error = store.errorMessage, previewBooks == nil, !query.isEmpty {
                        ContentUnavailableView {
                            Label("Search Unavailable", systemImage: "wifi.exclamationmark")
                        } description: { Text(error) }
                        actions: { Button("Try Again") { store.search(query: query) } }
                    } else if !query.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        ContentUnavailableView {
                            Label("Search Manga", systemImage: "magnifyingglass")
                        } description: { Text("Honbako.Search.EmptyHint") }
                        actions: { Button("Add Connection", action: openSettings) }
                    }
                }
            }
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .padding(.bottom, 16)
        }
        .background(Color(uiColor: .systemBackground))
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("Honbako.Search.Results")
        .onChange(of: presentation.query) { search() }
        .onAppear { search() }
        .onChange(of: presentation.isPresented) {
            if presentation.isPresented { search() } else { store.cancelSearch() }
        }
        .onDisappear { store.cancelSearch() }
    }

    private func search() {
        guard presentation.isPresented, previewBooks == nil else { return }
        if query.isEmpty { store.cancelSearch() } else { store.search(query: query) }
    }
}
#endif
