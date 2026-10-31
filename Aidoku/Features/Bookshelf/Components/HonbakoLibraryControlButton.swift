#if SUMI
import SwiftUI

struct HonbakoLibraryControlButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 20, weight: .semibold))
            // The glass is tinted dune in both schemes, so the symbol stays white.
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .contentShape(.circle)
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(reduceTransparency
                ? Color(uiColor: HonbakoPalette.scrubberUIColor) : HonbakoPalette.glassTint).interactive(), in: .circle)
    }
}
#endif
