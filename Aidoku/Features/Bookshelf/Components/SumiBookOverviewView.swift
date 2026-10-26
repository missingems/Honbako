#if SUMI
import SwiftUI

struct SumiBookOverviewView: View {
    let book: SumiBook
    let isSaved: Bool
    let isOpening: Bool
    let isUpdatingLibrary: Bool
    let hasUnfinishedBookmark: Bool
    let error: String?
    let openReader: () -> Void
    let toggleLibrary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SumiOpenBookView(book: book)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            SumiBookInformationView(
                book: book, isSaved: isSaved, isOpening: isOpening, isUpdatingLibrary: isUpdatingLibrary,
                hasUnfinishedBookmark: hasUnfinishedBookmark, error: error,
                openReader: openReader, toggleLibrary: toggleLibrary
            )
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
