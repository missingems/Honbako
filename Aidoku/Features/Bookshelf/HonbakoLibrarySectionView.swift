#if SUMI
import SwiftUI

struct HonbakoLibrarySectionView: View {
    let books: [SumiBook]
    let openingBookID: String?
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    var insertingBookID: String?
    var registerAnchor: ((String, SumiBookSourceAnchor) -> Void)?

    var body: some View {
        ForEach(books) { book in
            SumiGridCoverTile(book: book, openBook: openBook,
                registerAnchor: { anchor in registerAnchor?(book.presentation.id, anchor) })
                .overlay(alignment: .topTrailing) {
                    if book.unreadChapterCount > 0 {
                        Text(book.unreadChapterCount, format: .number)
                            .font(.caption.bold()).padding(.horizontal, 7).padding(.vertical, 4)
                            .foregroundStyle(.white)
                            .background(.red, in: .capsule)
                            .padding(5)
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)
                    }
                }
                .opacity(openingBookID == book.presentation.id || insertingBookID == book.presentation.id ? 0 : 1)
                .accessibilityHidden(openingBookID == book.presentation.id || insertingBookID == book.presentation.id)
                .id(book.presentation.id)
        }
    }
}
#endif
