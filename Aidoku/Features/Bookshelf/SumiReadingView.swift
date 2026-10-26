#if SUMI
import SwiftUI

struct SumiReadingView: View {
    @ObservedObject var store: SumiLibraryStore
    @ObservedObject var visibility: SumiLibraryVisibility
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    var findBooks: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    init(store: SumiLibraryStore, openBook: @escaping (SumiBook, SumiBookTransitionSource?) -> Void, visibility: SumiLibraryVisibility? = nil, findBooks: (() -> Void)? = nil) {
        self.store = store
        self.visibility = visibility ?? SumiLibraryVisibility()
        self.openBook = openBook
        self.findBooks = findBooks
    }

    var body: some View {
        Group {
            if store.library.isEmpty {
                if store.isLoading {
                    ProgressView("Loading library")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("Your library is ready", systemImage: "books.vertical")
                    } description: {
                        Text("Find a manga in Search, then add it to your library. Your books and reading progress will appear here.")
                    } actions: {
                        if let findBooks {
                            Button("Find books", systemImage: "magnifyingglass", action: findBooks)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            } else if reduceMotion || voiceOverEnabled {
                GeometryReader { geometry in
                    ScrollView {
                        SumiBookGrid(books: store.library, width: max(1, geometry.size.width - 32), openBook: openBook)
                            .padding(16)
                    }
                    .refreshable { await store.refresh() }
                }
            } else {
                SumiScatteredLibraryView(books: store.library, isObscured: visibility.isObscured, openBook: openBook)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .task { await store.refresh() }
    }
}
#endif
