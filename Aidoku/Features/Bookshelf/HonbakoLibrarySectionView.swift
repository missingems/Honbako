#if SUMI
import SwiftUI

struct HonbakoLibrarySectionView: View {
    let books: [SumiBook]
    let columns: [GridItem]
    let openingBookID: String?
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(books) { book in
                SumiGridCoverTile(book: book, openBook: openBook)
                    .overlay(alignment: .topTrailing) {
                        if book.unreadChapterCount > 0 {
                            Text(book.unreadChapterCount, format: .number)
                                .font(.caption.bold()).padding(.horizontal, 7).padding(.vertical, 4)
                                .background(.regularMaterial, in: .capsule)
                                .padding(5)
                                .accessibilityLabel("\(book.unreadChapterCount) unread chapters")
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if let date = book.finishedReadingAt {
                            Text(date, format: .dateTime.month(.abbreviated).day().year())
                                .font(.caption).lineLimit(1)
                                .padding(6).frame(maxWidth: .infinity)
                                .background(.regularMaterial)
                                .accessibilityLabel("Finished \(date.formatted(date: .abbreviated, time: .omitted))")
                        }
                    }
                    .opacity(openingBookID == book.presentation.id ? 0 : 1)
                    .accessibilityHidden(openingBookID == book.presentation.id)
            }
        }
    }
}
#endif
