#if SUMI
import SwiftUI

struct HonbakoLibrarySectionHeader: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(LocalizedStringKey(title))
            .font(.title2.bold())
            .foregroundStyle(Color.primary.shadow(.inner(
                color: contrast == .increased ? .clear
                    : colorScheme == .dark ? .black.opacity(0.28) : .white.opacity(0.22),
                radius: 0.7, x: 0, y: 0.75)))
            .padding(.horizontal, 16)
            .padding(.top, 34)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: .rect)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("Honbako.Library.Header.\(title)")
    }
}
#endif
