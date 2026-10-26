#if SUMI
import SwiftUI

struct HonbakoLibraryOnboardingView: View {
    let connect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your Library Starts Here").font(.title2.bold())
            Label("Add your own files or connect a personal server.", systemImage: "1.circle")
            Label("For another provider, add a source list or source file you trust.", systemImage: "2.circle")
            Label("Pull down to search, then choose Add to keep a manga here.", systemImage: "3.circle")
            Button("Add a Connection", systemImage: "link", action: connect)
                .buttonStyle(.borderedProminent)
            Link("Aidoku Community", destination: URL(string: "https://aidoku.app")!)
            Text("Use content you own or have permission to access. Community source suggestions do not grant content rights.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .font(.body)
        .frame(maxWidth: 540, alignment: .leading)
        .padding(24)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("Honbako.Library.Onboarding")
    }
}
#endif
