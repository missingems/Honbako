#if SUMI
import SwiftUI

/// A static open cover and facing description. The native presentation owns
/// the spatial transition from the library's real cover into this cover.
struct SumiOpenBookView: View {
    let book: SumiBook

    var body: some View {
        GeometryReader { geometry in
            let leafWidth = max(1, geometry.size.width / 2)
            let leafHeight = geometry.size.height - 16
            ZStack(alignment: .top) {
                Ellipse()
                    .fill(.black.opacity(0.2))
                    .frame(width: geometry.size.width * 0.82, height: 22)
                    .blur(radius: 16)
                    .offset(y: leafHeight - 1)
                    .accessibilityHidden(true)
                HStack(spacing: 0) {
                    BookCoverFace(book: book.presentation)
                        .overlay {
                            SumiBookZoomTarget()
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        .padding(3)
                        .background(book.presentation.accentColor.gradient)
                        .clipShape(.rect(cornerRadius: 4))
                        .overlay(alignment: .trailing) {
                            LinearGradient(colors: [.clear, .black.opacity(0.22)], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 18)
                                .allowsHitTesting(false)
                        }
                        .rotation3DEffect(.degrees(-9),
                                          axis: (x: 0, y: 1, z: 0), anchor: .trailing, perspective: 0.55)
                        .frame(width: leafWidth, height: leafHeight)
                        .zIndex(1)
                    SumiBookDescriptionPage(book: book)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .overlay(alignment: .leading) {
                            LinearGradient(colors: [.black.opacity(0.14), .black.opacity(0.035), .clear],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: 24)
                                .allowsHitTesting(false)
                        }
                        .clipShape(.rect(cornerRadius: 4))
                        .rotation3DEffect(.degrees(7),
                                          axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.55)
                        .frame(width: leafWidth, height: leafHeight)
                }
                .background {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(book.presentation.accentColor.opacity(0.8))
                        .padding(.horizontal, -3)
                        .offset(y: 5)
                }
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 10)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(1.36, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Sumi.Book.Open.\(book.presentation.id)")
    }
}
#endif
