#if SUMI
import SwiftUI

struct SumiSearchResultActionButton: View {
    let action: SumiSearchResultPresentation.Action
    let readingPosition: String?
    let bookTitle: String
    let bookID: String
    let adding: Bool
    let perform: () -> Void
    @ScaledMetric(relativeTo: .caption) private var positionWidth: CGFloat = 112

    private var identifier: String {
        let component: String
        switch action {
        case .get: component = "Add"
        case .read: component = "Read"
        case .resume: component = "Resume"
        }
        return "Sumi.Search.\(component).\(bookID)"
    }

    var body: some View {
        Button(action: perform) {
            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    if adding { ProgressView().controlSize(.small) }
                    Text(action.title).font(.caption.bold()).lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: .capsule)
                if action == .resume, let readingPosition {
                    Text(readingPosition)
                        .font(.caption)
                        .modifier(SumiVibrantSubtitleStyle())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: positionWidth)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(adding)
        .accessibilityLabel(String(localized: "\(action.title) \(bookTitle)"))
        .accessibilityValue(action == .resume ? readingPosition ?? "" : "")
        .accessibilityIdentifier(identifier)
    }
}
#endif
