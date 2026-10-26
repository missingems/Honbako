#if SUMI
import SwiftUI

struct SumiMainView: View {
    @ObservedObject var store: SumiLibraryStore
    @ObservedObject var discovery: SumiDiscoveryStore
    @ObservedObject var opening: SumiGridOpeningState
    @ObservedObject var search: SumiSearchPresentation
    let previewBooks: [SumiBook]?
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    let dismissSearch: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SumiGridContentView(store: store, discovery: discovery, opening: opening,
                                previewBooks: previewBooks, searchPresented: search.isPresented,
                                updateSearchPull: search.updatePull, finishSearchPull: finishSearchPull,
                                revealSearch: revealSearch,
                                searchRecommendation: { query in search.query = query; revealSearch() }, openBook: openBook)
                .allowsHitTesting(!search.isPresented)
                .accessibilityHidden(search.isPresented)
            SumiSpotlightSearchView(store: store, presentation: search, opening: opening,
                previewBooks: previewBooks, recommendations: discovery.books, openBook: openBook, dismiss: dismissSearch)
                .opacity(search.revealProgress)
                .allowsHitTesting(search.isPresented)
                .accessibilityHidden(!search.isPresented)
        }
        .animation(.easeInOut(duration: reduceMotion ? 0.12 : 0.22), value: search.isPresented)
        .background { Color(uiColor: .systemBackground).ignoresSafeArea() }
    }

    private func revealSearch() {
        guard opening.bookID == nil else { return }
        search.reveal()
    }

    private func finishSearchPull() {
        withAnimation(.smooth(duration: reduceMotion ? 0.12 : 0.28)) { search.finishPull() }
    }
}
#endif
