#if SUMI
import SwiftUI

/// The same full-bleed cover grid as the resolved library, without book details.
struct SumiLibraryLoadingView: View {
    let columns: [GridItem]
    let availableSize: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cardCount: Int {
        let count = max(1, columns.count)
        let width = max(1, (availableSize.width - CGFloat(count - 1) * 2) / CGFloat(count))
        let height = width / CGFloat(SumiGridBookPose.coverAspect)
        return count * max(2, Int(ceil(availableSize.height / (height + 2))))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<cardCount, id: \.self) { _ in
                    SumiLibraryLoadingCard(shimmerPhase: reduceMotion ? nil : phase)
                        .aspectRatio(CGFloat(SumiGridBookPose.coverAspect), contentMode: .fit)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading library")
        .accessibilityIdentifier("Honbako.Library.Loading")
    }
}
#endif
