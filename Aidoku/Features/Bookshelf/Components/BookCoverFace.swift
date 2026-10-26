#if SUMI
import NukeUI
import SwiftUI

struct BookCoverFace: View {
    let book: BookPresentation
    var isBack = false
    var showsBinding = true

    private var imageURL: URL? { isBack ? book.backCoverURL : book.coverURL }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let imageURL {
                    LazyImage(url: imageURL) { state in
                        if let image = state.image {
                            image.resizable().scaledToFill()
                        } else {
                            printedCover
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    printedCover
                }
                if showsBinding { LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.25), location: 0),
                        .init(color: .white.opacity(0.18), location: 0.018),
                        .init(color: .black.opacity(0.12), location: 0.035),
                        .init(color: .clear, location: 0.085),
                        .init(color: .clear, location: 0.86),
                        .init(color: .white.opacity(0.12), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ) }
            }
            .clipped()
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var printedCover: some View {
        if isBack {
            BookPrintedBackCover(book: book)
        } else {
            BookPrintedFrontCover(book: book)
        }
    }
}
#endif
