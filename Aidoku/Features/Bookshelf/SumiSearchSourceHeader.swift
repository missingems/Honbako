#if SUMI
import SwiftUI

struct SumiSearchSourceHeader: View {
    let name: String
    let sourceKey: String

    var body: some View {
        Text(name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: .rect)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("Honbako.Search.SourceHeader.\(sourceKey)")
    }
}
#endif
