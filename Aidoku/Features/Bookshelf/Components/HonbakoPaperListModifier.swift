#if SUMI
import SwiftUI

struct HonbakoPaperListModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background { HonbakoPaperBackground().ignoresSafeArea() }
    }
}

extension View {
    func honbakoPaperListBackground() -> some View { modifier(HonbakoPaperListModifier()) }

    func honbakoPaperRows() -> some View {
        listRowBackground(HonbakoPaperBackground(surface: .card))
    }
}
#endif
