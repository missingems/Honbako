#if SUMI
import SwiftUI

struct SumiGridContentView: View {
    @ObservedObject var store: SumiLibraryStore
    @ObservedObject var opening: SumiGridOpeningState
    @ObservedObject var insertion: SumiLibraryInsertionState
    let previewBooks: [SumiBook]?
    let revealSearch: () -> Void
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    @State private var order = SumiGridOrder()
    @State private var shelves = SumiLibraryShelves()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    private var isResolvingLibrary: Bool {
        store.loadState == .loading || (store.loadState == .loaded && !store.library.isEmpty
            && shelves.reading.isEmpty && shelves.finished.isEmpty)
    }

    var body: some View {
        GeometryReader { geometry in
            let count = dynamicTypeSize.isAccessibilitySize ? 2 : max(2, Int(geometry.size.width / 150))
            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: count)
            ScrollViewReader { scroll in
                ScrollView {
                    if let previewBooks {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(previewBooks) { book in
                                SumiGridCoverTile(book: book, openBook: openBook,
                                    registerAnchor: { insertion.register($0, for: book.presentation.id) })
                                    .opacity(opening.bookID == book.presentation.id || insertion.bookID == book.presentation.id ? 0 : 1)
                                    .accessibilityHidden(opening.bookID == book.presentation.id || insertion.bookID == book.presentation.id)
                                    .id(book.presentation.id)
                            }
                        }
                    } else if isResolvingLibrary {
                        SumiLibraryLoadingView(columns: columns, availableSize: geometry.size)
                    } else if case .failed(let message) = store.loadState {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle.scaled(by: 1.5))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            VStack(spacing: 8) {
                                Text("Library Couldn’t Load").font(.title2.bold())
                                Text(message).foregroundStyle(.secondary)
                            }
                            Button("Try Again", action: retryLoading)
                        }
                        .multilineTextAlignment(.center)
                        .padding(24)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("Honbako.Library.LoadError")
                        .frame(minHeight: max(0, geometry.size.height + geometry.safeAreaInsets.bottom - 32))
                    } else {
                        HonbakoLibraryShelvesView(shelves: shelves, columns: columns,
                            hideFinished: false, openingBookID: opening.bookID,
                            insertingBookID: insertion.bookID, openBook: openBook,
                            registerAnchor: { id, anchor in insertion.register(anchor, for: id) })
                        if shelves.visibleCount(hideFinished: false) == 0 {
                            HonbakoLibraryEmptyView(hasHiddenFinishedBooks: false,
                                showFinished: {}, findBooks: revealSearch)
                                .frame(minHeight: max(0, geometry.size.height + geometry.safeAreaInsets.bottom - 32))
                        }
                    }
                }
                .contentMargins(.bottom, 32, for: .scrollContent)
                .scrollBounceBehavior(.always, axes: .vertical)
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("Sumi.Grid")
                .accessibilityValue(String(localized: "\(previewBooks?.count ?? shelves.visibleCount(hideFinished: false)) manga"))
                .onChange(of: opening.returnRequest) {
                    updateLibrary()
                    guard let id = opening.returningBookID else { return }
                    let request = opening.returnRequest
                    Task { @MainActor in
                        await Task.yield()
                        guard opening.returnRequest == request, opening.returningBookID == id else { return }
                        if insertion.revealForReturn(bookID: id) == .unavailable {
                            // A single lazy grid resolves the stable book ID.
                            // No anchor asks SwiftUI for only the necessary reveal.
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) { scroll.scrollTo(id) }
                        }
                        await Task.yield()
                        guard opening.returnRequest == request, opening.returningBookID == id else { return }
                        opening.finishReturnLayout(request: request)
                    }
                }
                .onChange(of: insertion.scrollRequest) {
                    guard let bookID = insertion.bookID else { return }
                    updateLibrary()
                    // Insert the saved model before asking the lazy grid for
                    // its cover. Search still covers this repositioning.
                    Task { @MainActor in
                        await Task.yield()
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { scroll.scrollTo(bookID, anchor: .center) }
                    }
                }
            }
        }
        .ignoresSafeArea(.container, edges: [.top, .leading, .trailing])
        .background { Color(uiColor: .systemBackground).ignoresSafeArea() }
        .task { await prepareLibrary() }
        .onChange(of: store.library) { updateLibrary() }
        .onChange(of: store.loadState) { updateLibrary() }
        .onChange(of: opening.bookID) { if opening.bookID == nil { updateLibrary() } }
        .onChange(of: scenePhase) {
            if scenePhase == .active, previewBooks == nil {
                Task { await store.refresh() }
            }
        }
    }

    private func prepareLibrary() async {
        guard previewBooks == nil else { return }
        updateLibrary()
        await store.refresh()
        updateLibrary()
    }

    private func retryLoading() {
        Task { await store.refresh() }
    }

    private func updateLibrary() {
        guard previewBooks == nil, store.loadState == .loaded else { return }
        // The receiving slot must remain still while its exact closed print
        // hands over to SwiftUI, even after the source has been revealed.
        guard !(opening.isPreparingReturn && opening.returnLayoutComplete),
              opening.bookID == nil || opening.returningBookID != nil else { return }
        let books = order.books(catalog: [], library: store.library)
        shelves = SumiLibraryShelves(books: books, stableIDs: order.identifiers,
            tutorialIdentifier: .init(sourceKey: HonbakoTutorialManga.sourceKey, mangaKey: HonbakoTutorialManga.mangaKey))
    }
}
#endif
