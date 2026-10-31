#if SUMI
import SwiftUI

struct HonbakoLibraryControls: View {
    let revealSearch: () -> Void
    let showSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            HonbakoLibraryControlButton(title: "Search Manga", systemImage: "magnifyingglass", action: revealSearch)
                .accessibilityIdentifier("Honbako.Library.Search")
            HonbakoLibraryControlButton(title: "Settings", systemImage: "gearshape", action: showSettings)
                .accessibilityIdentifier("Honbako.Library.Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
#endif
