#if SUMI
import SwiftUI

/// Follow the container's live bar axis, including rotations and fold changes.
@available(iOS 27.1, *)
struct HonbakoLibrarySearchToolbar: ToolbarContent {
    @Environment(\.toolbarVerticalEdge) private var verticalEdge
    @ObservedObject var search: SumiSearchPresentation
    let revealSearch: () -> Void
    let dismissSearch: () -> Void

    var body: some ToolbarContent {
        if verticalEdge != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Search Manga", systemImage: "magnifyingglass", action: revealSearch)
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("Honbako.Library.Search")
            }
            .axisBehavior(.verticalPreferred)
            .visibilityPriority(.high)
        } else {
            ToolbarItem(placement: .principal) {
                SumiNativeSearchField(text: $search.query, requestsKeyboard: false, entryOnly: true,
                    dismiss: dismissSearch, keyboardDismissed: {}, beginSearch: revealSearch)
                    .frame(minWidth: 80, idealWidth: 220, maxWidth: .infinity)
                    .accessibilityHidden(search.isPresented)
            }
            .axisBehavior(.horizontalOnly)
            .visibilityPriority(.high)
        }
    }
}
#endif
