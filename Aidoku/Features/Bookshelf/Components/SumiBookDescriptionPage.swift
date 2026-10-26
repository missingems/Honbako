#if SUMI
import SwiftUI

/// The complete source description stays on the facing paper and scrolls
/// independently, including when Dynamic Type needs more room.
struct SumiBookDescriptionPage: View {
    let book: SumiBook

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let author = book.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(book.editionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let blurb = book.blurb, !blurb.isEmpty {
                    Text(blurb)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } else {
                    Text("No description is available for this edition.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.primary)
    }
}
#endif
