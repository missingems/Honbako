#if SUMI
import SwiftUI

struct SumiPublicationStatusBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .textCase(.uppercase)
            .modifier(SumiVibrantSubtitleStyle())
            .lineLimit(1)
    }
}
#endif
