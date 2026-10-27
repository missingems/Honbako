#if SUMI
import SwiftUI

struct HonbakoLibrarySectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.largeTitle.bold())
            .padding(.horizontal, 16)
            .padding(.top, 21)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: .rect)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("Honbako.Library.Header.\(title)")
    }
}
#endif
