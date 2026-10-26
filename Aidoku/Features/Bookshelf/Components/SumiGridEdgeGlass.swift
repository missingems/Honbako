#if SUMI
import SwiftUI

/// A narrow, feathered lens at the viewport edge. The center of the grid remains
/// untouched; the mask reveals native refraction rather than drawing a border.
struct SumiGridEdgeGlass: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(18)))
        Color.clear
            .glassEffect(.clear, in: shape)
            .mask {
                shape.stroke(lineWidth: 8).blur(radius: 3)
            }
            .opacity(reduceTransparency ? 0 : 0.45)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
#endif
