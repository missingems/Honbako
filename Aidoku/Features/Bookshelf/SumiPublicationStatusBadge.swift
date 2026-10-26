#if SUMI
import SwiftUI

struct SumiPublicationStatusBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .modifier(SumiVibrantSubtitleStyle())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: .capsule)
            .fixedSize()
    }
}
#endif
