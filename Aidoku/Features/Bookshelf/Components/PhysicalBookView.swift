#if SUMI
import SwiftUI

/// A static physical cover. The enclosing button owns navigation; the book
/// never intercepts scrolling gestures.
struct PhysicalBookView: View {
    let book: BookPresentation
    var style: PhysicalBookStyle = .shelf

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let height = max(1, geometry.size.height)
            let bookWidth = max(1, min(geometry.size.width * 0.76, height * 0.82 * 0.68))
            let bookHeight = bookWidth / 0.68
            let center = CGPoint(x: geometry.size.width / 2, y: height * 0.45)
            ZStack(alignment: .topLeading) {
                Ellipse()
                    .fill(.black.opacity(0.15))
                    .frame(width: bookWidth * 0.95, height: bookWidth * 0.12)
                    .blur(radius: bookWidth * 0.045)
                    .position(x: center.x + bookWidth * 0.035, y: center.y + bookHeight / 2 + bookWidth * 0.045)
                PhysicalBookMesh(
                    book: book, canvasSize: geometry.size,
                    bookSize: CGSize(width: bookWidth, height: bookHeight),
                    thickness: max(10, bookWidth * (style == .detail ? 0.095 : 0.085)), center: center,
                    yaw: reduceMotion ? 0 : book.restingYaw,
                    pitch: reduceMotion ? 0 : book.restingPitch
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .rotationEffect(.degrees(reduceMotion ? 0 : book.restingTilt * (style == .detail ? 0.3 : 1)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(book.title + (book.author.isEmpty ? "" : ", by " + book.author))
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(.isImage)
        }
        .aspectRatio(0.75, contentMode: .fit)
    }

    private var accessibilityValue: String {
        let position = book.readingPositionLabel
        guard let progress = book.normalizedProgress else { return position }
        return [position, "Bookmark at \(Int((progress * 100).rounded())) percent of the current chapter"]
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
#endif
