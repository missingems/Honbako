#if SUMI
import SwiftUI

struct BookPrintedBackCover: View {
    let book: BookPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(book.title).font(.headline).lineLimit(3)
            if !book.author.isEmpty { Text(book.author).font(.subheadline).lineLimit(2) }
            if !book.blurb.isEmpty { Text(book.blurb).font(.caption).lineLimit(8) }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.background.secondary)
        .accessibilityHidden(true)
    }
}
#endif
