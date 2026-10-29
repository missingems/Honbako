#if SUMI
import SwiftUI

struct HonbakoLibraryEmptyView: View {
    let hasHiddenFinishedBooks: Bool
    let showFinished: () -> Void
    let findBooks: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(LocalizedStringKey(hasHiddenFinishedBooks ? "Honbako.Library.Hidden.Title" : "Honbako.Library.Empty.Title"),
                systemImage: hasHiddenFinishedBooks ? "checkmark.circle" : "books.vertical")
        } description: {
            Text(LocalizedStringKey(hasHiddenFinishedBooks ? "Honbako.Library.Hidden.Detail" : "Honbako.Library.Empty.Detail"))
        } actions: {
            if hasHiddenFinishedBooks {
                Button("Honbako.Library.ShowFinished", action: showFinished)
            } else {
                Button("Honbako.Library.FindBooks", action: findBooks)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .accessibilityIdentifier("Honbako.Library.Empty")
    }
}
#endif
