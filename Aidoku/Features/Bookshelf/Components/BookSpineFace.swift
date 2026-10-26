#if SUMI
import SwiftUI

struct BookSpineFace: View {
    let book: BookPresentation

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                book.accentColor
                LinearGradient(colors: [.black.opacity(0.22), .clear, .white.opacity(0.15), .black.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                Text(book.title)
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0.99, green: 0.97, blue: 0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: max(1, geometry.size.height - 32))
                    .rotationEffect(.degrees(90))
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                VStack {
                    Rectangle().fill(.white.opacity(0.5)).frame(height: 0.65)
                    Spacer()
                    Rectangle().fill(.white.opacity(0.5)).frame(height: 0.65)
                }
                .padding(.vertical, 10)
            }
            .clipped()
        }
        .accessibilityHidden(true)
    }
}
#endif
