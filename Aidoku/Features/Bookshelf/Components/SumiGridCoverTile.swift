#if SUMI
import SwiftUI

struct SumiGridCoverTile: View {
    let book: SumiBook
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    var registerAnchor: ((SumiBookSourceAnchor) -> Void)?
    @State private var anchor = SumiBookSourceAnchor()

    var body: some View {
        Button {
            openBook(book, anchor.view.flatMap { SumiBookTransitionSource.capture($0, replacementView: { anchor.view }) })
        } label: {
            SumiGridBookRepresentable(book: book, anchor: anchor)
                .aspectRatio(CGFloat(SumiGridBookPose.coverAspect), contentMode: .fit)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(book.title)
        .accessibilityValue([book.chapterLabel, book.pageLabel].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(String(localized: "Open manga"))
        .accessibilityIdentifier("Sumi.Grid.Book.\(book.presentation.id)")
        .onAppear { registerAnchor?(anchor) }
    }
}
#endif
