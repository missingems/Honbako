#if SUMI
import SwiftUI

struct BookPrintedFrontCover: View {
    let book: BookPresentation

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(book.title)
                .font(.headline)
                .lineLimit(4)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.secondary)
        .accessibilityHidden(true)
    }
}
#endif
