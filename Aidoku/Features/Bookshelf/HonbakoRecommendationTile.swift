#if SUMI
import SwiftUI

struct HonbakoRecommendationTile: View {
    let item: HonbakoRecommendationFeed.Item
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 5) {
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let url = item.coverURL {
                        AsyncImage(url: url) { image in image.resizable().scaledToFill() }
                            placeholder: { Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(.secondary) }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "book.closed").font(.largeTitle)
                            Text(item.title).font(.headline).multilineTextAlignment(.center).lineLimit(4)
                        }
                        .foregroundStyle(.secondary)
                        .padding(12)
                    }
                }
                .aspectRatio(0.68, contentMode: .fit)
                .clipped()
                Text(item.title).font(.subheadline).lineLimit(2)
            }
            .padding(.bottom, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityHint("Search your connections for this manga")
        .contextMenu {
            if let url = item.officialURL { Link("Publisher Website", destination: url) }
        }
    }
}
#endif
