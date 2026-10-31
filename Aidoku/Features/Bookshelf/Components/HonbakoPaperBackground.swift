#if SUMI
import SwiftUI

struct HonbakoPaperBackground: View {
    var surface: HonbakoPaperStock.Surface = .page
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if contrast == .increased {
                Color(uiColor: HonbakoPaperStock.base(dark: scheme == .dark, surface: surface))
            } else {
                Image(uiImage: HonbakoPaperStock.tile(dark: scheme == .dark, surface: surface))
                    .resizable(resizingMode: .tile)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
#endif
