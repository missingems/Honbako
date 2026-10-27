#if SUMI
import SwiftUI

struct HonbakoSettingsRowBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Color(uiColor: .secondarySystemGroupedBackground)
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}
#endif
