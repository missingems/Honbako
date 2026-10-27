#if SUMI
import SwiftUI

struct BookPrintedFrontCover: View {
    let book: BookPresentation

    var body: some View {
        Text(book.title)
            .font(.body.weight(.medium))
            .lineLimit(4)
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.secondary)
        .accessibilityHidden(true)
    }
}
#endif
