#if SUMI
import SwiftUI

struct SumiSearchView: View {
    @ObservedObject var store: SumiLibraryStore
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    let retry: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    if store.isSearching {
                        ProgressView()
                            .accessibilityLabel("Searching")
                            .frame(maxWidth: .infinity, minHeight: 100)
                    } else if store.searchResults.isEmpty {
                        ContentUnavailableView {
                            Label(store.errorMessage == nil ? "No results" : "Couldn’t load books",
                                  systemImage: store.errorMessage == nil ? "magnifyingglass" : "wifi.exclamationmark")
                        } actions: {
                            if store.errorMessage != nil { Button("Retry", action: retry) }
                        }
                    }
                    SumiBookGrid(books: store.searchResults, width: max(1, geometry.size.width - 32), openBook: openBook)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(SumiTheme.paper)
    }
}
#endif
