#if SUMI
import SwiftUI

struct HonbakoRecommendationTile: View {
    let item: HonbakoRecommendationFeed.Item
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            ZStack {
                Rectangle().fill(.quaternary)
                AsyncImage(url: item.coverURL) { image in image.resizable().scaledToFill() }
                    placeholder: {
                    Text(item.title).font(.body.weight(.medium)).multilineTextAlignment(.center).lineLimit(4)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .aspectRatio(0.68, contentMode: .fit)
            .clipped()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityHint(String(localized: "Search your connections for this manga"))
        .contextMenu {
            if let url = item.officialURL { Link("Publisher Website", destination: url) }
        }
    }
}
#endif
