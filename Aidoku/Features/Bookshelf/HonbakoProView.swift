#if SUMI
import SwiftUI

struct HonbakoProView: View {
    let feature: HonbakoProFeature?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HonbakoSubscriptionPlansView(feature: feature)
                .navigationTitle("Honbako Pro")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") { dismiss() }
                    }
                }
        }
        .tint(HonbakoPalette.accent)
    }
}
#endif
