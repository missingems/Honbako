#if SUMI
import SwiftUI

struct SumiGridContentView: View {
    @ObservedObject var store: SumiLibraryStore
    @ObservedObject var discovery: SumiDiscoveryStore
    @ObservedObject var opening: SumiGridOpeningState
    let previewBooks: [SumiBook]?
    let searchPresented: Bool
    let updateSearchPull: (CGFloat) -> Void
    let finishSearchPull: () -> Void
    let revealSearch: () -> Void
    let searchRecommendation: (String) -> Void
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    @StateObject private var recommendations = HonbakoRecommendationStore()
    @State private var order = SumiGridOrder()
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var pullDistance: CGFloat = 0
    @State private var libraryBooks: [SumiBook] = []
    @State private var hasPreparedLibrary = false
    @State private var connectionsPresented = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    private var reading: [SumiBook] { SumiLibraryShelfSummary.readingOrder(libraryBooks, stableIDs: order.identifiers) }
    private var finished: [SumiBook] {
        libraryBooks.filter { $0.finishedReadingAt != nil }
            .sorted { ($0.finishedReadingAt ?? .distantPast) > ($1.finishedReadingAt ?? .distantPast) }
    }

    var body: some View {
        GeometryReader { geometry in
            let count = dynamicTypeSize.isAccessibilitySize ? 2 : max(2, Int(geometry.size.width / 150))
            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: count)
            ScrollView {
                if let previewBooks {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(previewBooks) { book in
                            SumiGridCoverTile(book: book, openBook: openBook)
                                .opacity(opening.bookID == book.presentation.id ? 0 : 1)
                                .accessibilityHidden(opening.bookID == book.presentation.id)
                        }
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        if hasPreparedLibrary, libraryBooks.isEmpty {
                            HonbakoLibraryOnboardingView { connectionsPresented = true }
                        }
                        HonbakoLibrarySectionView(title: "Finished", books: finished, columns: columns,
                            openingBookID: opening.bookID, openBook: openBook)
                        HonbakoLibrarySectionView(title: "Reading", books: reading, columns: columns,
                            openingBookID: opening.bookID, openBook: openBook)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recommendations").font(.title2.bold()).padding(.horizontal, 16)
                            if recommendations.items.isEmpty {
                                Text("Suggestions will appear when the catalog is available.")
                                    .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 16)
                            } else {
                                LazyVGrid(columns: columns, spacing: 2) {
                                    ForEach(recommendations.items) { item in
                                        HonbakoRecommendationTile(item: item) { searchRecommendation(item.searchQuery) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, max(16, geometry.safeAreaInsets.top))
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
            .accessibilityValue("\(previewBooks?.count ?? libraryBooks.count) manga")
        }
        .ignoresSafeArea(.container)
        .background { Color(uiColor: .systemBackground).ignoresSafeArea() }
        .sheet(isPresented: $connectionsPresented) { SumiSourcesView() }
        .task { await prepareLibrary() }
        .onChange(of: store.library) { updateLibrary() }
        .onChange(of: opening.bookID) { if opening.bookID == nil { updateLibrary() } }
        .onChange(of: scenePhase) {
            if scenePhase == .active, previewBooks == nil {
                Task { await store.refresh(); await recommendations.refresh() }
            }
        }
    }

    private func prepareLibrary() async {
        guard previewBooks == nil, !hasPreparedLibrary else { return }
        await store.refresh()
        hasPreparedLibrary = true
        updateLibrary()
        await recommendations.refresh()
    }

    private func updateLibrary() {
        guard previewBooks == nil, hasPreparedLibrary, opening.bookID == nil else { return }
        libraryBooks = order.books(catalog: [], library: store.library)
    }
}
#endif
