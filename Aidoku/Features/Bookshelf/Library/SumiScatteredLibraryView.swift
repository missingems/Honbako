#if SUMI
import SwiftUI

struct SumiScatteredLibraryView: View {
    let books: [SumiBook]
    var isObscured = false
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    @State private var isVisible = false

    var body: some View {
        SumiBookPileRepresentable(books: books, isActive: isVisible && !isObscured, openBook: openBook)
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
    }
}
#endif
