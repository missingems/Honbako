#if SUMI
import SwiftUI

struct SumiVibrantSubtitleStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.foregroundStyle(.secondary)
        } else {
            content
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.6))
                .compositingGroup()
                .blendMode(colorScheme == .dark ? .plusLighter : .plusDarker)
        }
    }
}
#endif
