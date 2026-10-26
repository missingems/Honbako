#if SUMI
import SwiftUI

struct SumiBookPileRepresentable: UIViewRepresentable {
    let books: [SumiBook]
    let isActive: Bool
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void

    func makeUIView(context: Context) -> SumiBookPileView { SumiBookPileView() }

    func updateUIView(_ view: SumiBookPileView, context: Context) {
        view.openBook = openBook
        view.setBooks(books)
        view.setActive(isActive)
    }

    static func dismantleUIView(_ view: SumiBookPileView, coordinator: ()) { view.tearDown() }
}
#endif
