#if SUMI
import SwiftUI

struct HonbakoLibrarySectionHeader: View {
    let title: String
    var body: some View {
        Text(LocalizedStringKey(title))
            .font(.title2.bold())
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .systemBackground))
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("Honbako.Library.Header.\(title)")
    }
}
#endif
