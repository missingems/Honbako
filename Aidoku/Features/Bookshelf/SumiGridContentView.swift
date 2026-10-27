#if SUMI
import SwiftUI

struct SumiGridContentView: View {
    @ObservedObject var store: SumiLibraryStore
    @ObservedObject var opening: SumiGridOpeningState
    @ObservedObject var insertion: SumiLibraryInsertionState
    let previewBooks: [SumiBook]?
    let searchPresented: Bool
    let updateSearchPull: (CGFloat) -> Void
    let finishSearchPull: () -> Void
    let revealSearch: () -> Void
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    @State private var order = SumiGridOrder()
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var pullDistance: CGFloat = 0
    @State private var libraryBooks: [SumiBook] = []
    @State private var hasPreparedLibrary = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    private var reading: [SumiBook] {
        SumiLibraryShelfSummary.readingOrder(libraryBooks, stableIDs: order.identifiers,
            tutorialIdentifier: .init(sourceKey: HonbakoTutorialManga.sourceKey, mangaKey: HonbakoTutorialManga.mangaKey))
    }
    private var finished: [SumiBook] {
        libraryBooks.filter { $0.finishedReadingAt != nil }
            .sorted { ($0.finishedReadingAt ?? .distantPast) > ($1.finishedReadingAt ?? .distantPast) }
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
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            if !finished.isEmpty {
                                Section {
                                    HonbakoLibrarySectionView(books: finished, columns: columns,
                                        openingBookID: opening.bookID, openBook: openBook,
                                        insertingBookID: insertion.bookID,
                                        registerAnchor: { id, anchor in insertion.register(anchor, for: id) })
                                } header: {
                                    HonbakoLibrarySectionHeader(title: "Finished")
                                }
                            }
                            if !reading.isEmpty {
                                Section {
                                    HonbakoLibrarySectionView(books: reading, columns: columns,
                                        openingBookID: opening.bookID, openBook: openBook,
                                        insertingBookID: insertion.bookID,
                                        registerAnchor: { id, anchor in insertion.register(anchor, for: id) })
                                } header: {
                                    HonbakoLibrarySectionHeader(title: "Reading")
                                }
                            }
                        }
                        .padding(.bottom, max(16, geometry.safeAreaInsets.bottom))
                        if !hasPreparedLibrary { ProgressView().padding(24).accessibilityLabel("Loading library") }
                    }
                }
                .contentMargins(0, for: .scrollContent)
                .scrollBounceBehavior(.always, axes: .vertical)
                .onScrollPhaseChange { old, phase in
                    scrollPhase = phase
                    if old == .interacting, phase != .interacting, !searchPresented {
                        if pullDistance >= 52 { revealSearch() } else { finishSearchPull() }
                        pullDistance = 0
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                    guard scrollPhase == .interacting, !searchPresented else { return }
                    pullDistance = max(0, -offset)
                    updateSearchPull(pullDistance)
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("Sumi.Grid")
                .accessibilityValue(String(localized: "\(previewBooks?.count ?? libraryBooks.count) manga"))
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
        .ignoresSafeArea(.container)
        .background { Color(uiColor: .systemBackground).ignoresSafeArea() }
        .task { await prepareLibrary() }
        .onChange(of: store.library) { updateLibrary() }
        .onChange(of: opening.bookID) { if opening.bookID == nil { updateLibrary() } }
        .onChange(of: scenePhase) {
            if scenePhase == .active, previewBooks == nil {
                Task { await store.refresh() }
            }
        }
    }

    private func prepareLibrary() async {
        guard previewBooks == nil, !hasPreparedLibrary else { return }
        await store.refresh()
        hasPreparedLibrary = true
        updateLibrary()
    }

    private func updateLibrary() {
        guard previewBooks == nil, hasPreparedLibrary, opening.bookID == nil else { return }
        libraryBooks = order.books(catalog: [], library: store.library)
    }
}
#endif
