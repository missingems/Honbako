#if SUMI
import SwiftUI

struct HonbakoLibraryEmptyView: View {
    let hasHiddenFinishedBooks: Bool
    let showFinished: () -> Void
    let findBooks: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasHiddenFinishedBooks ? "checkmark.circle" : "books.vertical")
                .font(.largeTitle.scaled(by: 1.5))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(LocalizedStringKey(hasHiddenFinishedBooks ? "Honbako.Library.Hidden.Title" : "Honbako.Library.Empty.Title"))
                    .font(.title2.bold())
                Text(LocalizedStringKey(hasHiddenFinishedBooks ? "Honbako.Library.Hidden.Detail" : "Honbako.Library.Empty.Detail"))
                    .foregroundStyle(.secondary)
            }
            if hasHiddenFinishedBooks {
                Button("Honbako.Library.ShowFinished", action: showFinished)
            } else {
                Button("Honbako.Library.FindBooks", action: findBooks)
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Honbako.Library.Empty")
    }
}
#endif
