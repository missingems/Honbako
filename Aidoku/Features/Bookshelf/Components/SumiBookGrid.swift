#if SUMI
import SwiftUI

struct SumiBookGrid: View {
    let books: [SumiBook]
    let width: CGFloat
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: Int {
        if dynamicTypeSize.isAccessibilitySize { return 1 }
        let fitting = max(1, Int((width + 16) / 176))
        // Keep a center aisle in wide book layouts and allow one column in a
        // genuinely narrow window instead of crushing two covers together.
        return width >= 600 ? max(2, fitting / 2 * 2) : fitting
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: columns),
                  alignment: .leading, spacing: 16) {
            ForEach(books) { book in
                SumiBookGridButton(book: book, openBook: openBook)
            }
        }
    }
}
private struct SumiBookGridButton: View {
    let book: SumiBook
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    @State private var anchor = SumiBookSourceAnchor()

    var body: some View {
        Button {
            let source = anchor.view.flatMap { SumiBookTransitionSource.capture($0) }
            openBook(book, source)
        } label: {
            SumiBookGridCell(book: book)
                .overlay { SumiBookSourceView(anchor: anchor).allowsHitTesting(false) }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([book.title, book.author, book.editionLabel, book.chapterLabel, book.pageLabel].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Open book")
    }
}
#endif
