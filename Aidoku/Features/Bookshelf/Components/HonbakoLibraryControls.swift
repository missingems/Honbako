#if SUMI
import SwiftUI

struct HonbakoLibraryControls: View {
    let revealSearch: () -> Void
    let showSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            Button("Search Manga", systemImage: "magnifyingglass", action: revealSearch)
                .accessibilityIdentifier("Honbako.Library.Search")
            Button("Settings", systemImage: "gearshape", action: showSettings)
                .accessibilityIdentifier("Honbako.Library.Settings")
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 20, weight: .semibold))
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
#endif
