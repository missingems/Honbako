#if SUMI
import SwiftUI

struct SumiChapterRow: View {
    let chapter: SumiChapterSnapshot
    let isOpening: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let subtitle = chapter.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(chapter.progressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let progress = chapter.progressFraction {
                    ProgressView(value: progress)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 8)
            if isOpening {
                ProgressView()
            } else if !chapter.canRead {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Unavailable")
            } else if chapter.completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else if chapter.isCurrent {
                Image(systemName: "book.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Current chapter")
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
#endif
