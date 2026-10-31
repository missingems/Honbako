#if SUMI
import SwiftUI

struct HonbakoLibraryShelvesView: View {
    let shelves: SumiLibraryShelves
    let columns: [GridItem]
    let hideFinished: Bool
    let openingBookID: String?
    let insertingBookID: String?
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    var registerAnchor: ((String, SumiBookSourceAnchor) -> Void)?

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            if !shelves.reading.isEmpty {
                HonbakoLibrarySectionView(books: shelves.reading,
                    openingBookID: openingBookID, openBook: openBook,
                    insertingBookID: insertingBookID, registerAnchor: registerAnchor)
            }
            if !hideFinished, !shelves.finished.isEmpty {
                HonbakoLibrarySectionView(books: shelves.finished,
                    openingBookID: openingBookID, openBook: openBook,
                    insertingBookID: insertingBookID, registerAnchor: registerAnchor)
            }
        }
    }
}
#endif
