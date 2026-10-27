#if SUMI
import SwiftUI

struct HonbakoLibrarySectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .padding(.horizontal, 16)
            .padding(.top, 21)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("Honbako.Library.Header.\(title)")
    }
}
#endif
