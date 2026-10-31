#if SUMI
import SwiftUI

struct SumiBookInformationView: View {
    let book: SumiBook
    let isSaved: Bool
    let isOpening: Bool
    let isUpdatingLibrary: Bool
    let hasUnfinishedBookmark: Bool
    let error: String?
    let openReader: () -> Void
    let toggleLibrary: () -> Void

    @State private var showingCoverPro = false

    private var hasBookmark: Bool { book.chapterLabel != nil || book.pageLabel != nil }
    private var readingAction: String {
        if hasUnfinishedBookmark { return "Open bookmark" }
        return book.lastRead == nil ? "Read" : "Continue reading"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if hasBookmark {
                Text([book.chapterLabel, book.pageLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: openReader) {
                HStack(spacing: 8) {
                    if isOpening { ProgressView() }
                    Text(readingAction)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(HonbakoPalette.action)
            .foregroundStyle(HonbakoPalette.onAction)
            .controlSize(.large)
            .disabled(isOpening || isUpdatingLibrary)
            .accessibilityIdentifier("SumiReadBook")
            Button(action: toggleLibrary) {
                HStack(spacing: 8) {
                    if isUpdatingLibrary { ProgressView() }
                    Label(isSaved ? "Remove from Reading" : "Add to Reading",
                          systemImage: isSaved ? "checkmark" : "plus")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isOpening || isUpdatingLibrary)
            if HonbakoDeviceModel.isPhoneDuo {
                HonbakoMangaCoverModeControl(mangaID: book.id, requestPro: { showingCoverPro = true })
            }
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("SumiReadingError")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingCoverPro) { HonbakoProView(feature: .coverDisplay) }
    }
}
#endif
