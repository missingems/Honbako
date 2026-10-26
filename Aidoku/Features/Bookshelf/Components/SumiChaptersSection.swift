#if SUMI
import SwiftUI

struct SumiChaptersSection: View {
    let chapters: [SumiChapterSnapshot]
    let isLoading: Bool
    let isOpening: Bool
    let openingChapterID: ChapterIdentifier?
    let error: String?
    let openChapter: (SumiChapterSnapshot) -> Void
    let reload: () -> Void

    var body: some View {
        Section("Chapters") {
            if isLoading && chapters.isEmpty {
                ProgressView("Loading chapters")
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if chapters.isEmpty {
                ContentUnavailableView(
                    "No chapters available",
                    systemImage: "book.closed",
                    description: Text(error ?? "This provider has no chapters available for this edition.")
                )
                Button("Reload chapters", systemImage: "arrow.clockwise", action: reload)
            } else {
                ForEach(chapters) { chapter in
                    Button {
                        openChapter(chapter)
                    } label: {
                        SumiChapterRow(chapter: chapter, isOpening: openingChapterID == chapter.id)
                    }
                    .buttonStyle(.plain)
                    .disabled(!chapter.canRead || isOpening)
                }
            }
        }
    }
}
#endif
