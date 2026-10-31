#if SUMI
import SwiftUI

struct SumiMainView: View {
    @ObservedObject var store: SumiLibraryStore
    @ObservedObject var opening: SumiGridOpeningState
    @ObservedObject var search: SumiSearchPresentation
    @ObservedObject var insertion: SumiLibraryInsertionState
    let previewBooks: [SumiBook]?
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    let dismissSearch: () -> Void
    let didAddBook: (SumiBook, SumiBookTransitionSource?) async -> Void
    @State private var sourcesPresented = false
    @State private var welcomePresented = false
    @AppStorage(HonbakoWelcomeGate.completionKey) private var welcomeCompletedVersion = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                SumiGridContentView(store: store, opening: opening, insertion: insertion,
                    previewBooks: previewBooks,
                    revealSearch: revealSearch, openBook: openBook)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        HonbakoLibraryControls(revealSearch: revealSearch, showSettings: {
                            search.suspendKeyboard()
                            sourcesPresented = true
                        })
                        .ignoresSafeArea(.container, edges: .horizontal)
                    }
                    .allowsHitTesting(!search.isPresented && insertion.bookID == nil)
                    .accessibilityHidden(search.isPresented)
                SumiSpotlightSearchView(store: store, presentation: search, opening: opening, insertion: insertion,
                    previewBooks: previewBooks, openBook: openBook, dismiss: dismissSearch,
                    didAddBook: didAddBook)
                    .opacity(search.isPresented ? 1 : 0)
                    .allowsHitTesting(search.isPresented)
                    .accessibilityHidden(!search.isPresented)
            }
            .background { Color(uiColor: .systemBackground).ignoresSafeArea() }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.25), value: search.isPresented)
        }
        .sheet(isPresented: $sourcesPresented, onDismiss: refreshSearch) { SumiSourcesView() }
        .fullScreenCover(isPresented: $welcomePresented) {
            HonbakoWelcomeView(onFinish: finishWelcome)
                .interactiveDismissDisabled()
        }
        .task { presentWelcomeIfNeeded() }
        .onChange(of: search.isPresented) {
            if !search.isPresented { dismissSearch() }
        }
    }

    private func presentWelcomeIfNeeded() {
        // Subscription restoration is independent of this installation's intro.
        welcomePresented = HonbakoWelcomeGate.shouldPresent(completedVersion: welcomeCompletedVersion,
            hasPreviewBooks: previewBooks != nil, arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment)
    }

    private func finishWelcome() {
        let version = HonbakoWelcomeGate.completionVersion(from: welcomeCompletedVersion, arguments: ProcessInfo.processInfo.arguments)
        if version != welcomeCompletedVersion { welcomeCompletedVersion = version }
        welcomePresented = false
    }

    private func revealSearch() {
        guard opening.bookID == nil else { return }
        search.reveal()
    }

    private func refreshSearch() {
        guard search.isPresented, previewBooks == nil else { return }
        let query = search.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { store.search(query: query) }
    }
}
#endif
