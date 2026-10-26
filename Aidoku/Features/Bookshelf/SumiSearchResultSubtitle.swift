#if SUMI
import SwiftUI

struct SumiSearchResultSubtitle: View {
    let author: String?
    let presentation: SumiSearchResultPresentation
    var languages: SumiSearchLanguageInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let publication = presentation.publicationSubtitle {
                    ViewThatFits(in: .horizontal) {
                        Text(publication).fixedSize(horizontal: true, vertical: false)
                        if let compact = presentation.compactPublicationSubtitle {
                            Text(compact)
                        }
                    }
                    .font(.caption)
                    .lineLimit(1)
                    .modifier(SumiVibrantSubtitleStyle())
                }
                if let badge = presentation.publicationBadge {
                    SumiPublicationStatusBadge(title: badge)
                }
            }
            if let author {
                Text(author).font(.subheadline).lineLimit(1)
                    .modifier(SumiVibrantSubtitleStyle())
            }
            if let languages {
                ViewThatFits(in: .horizontal) {
                    Text(languages.text).fixedSize(horizontal: true, vertical: false)
                    Text(languages.compactText)
                }
                .font(.caption)
                .lineLimit(1)
                .modifier(SumiVibrantSubtitleStyle())
                .accessibilityLabel(languages.accessibilityText)
            }
        }
    }
}
#endif
