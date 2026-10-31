#if SUMI
import SwiftUI

/// Public support and creator details, presented with native settings rows.
struct HonbakoContactSection: View {
    var body: some View {
        Section {
            if let supportURL = URL(string: "mailto:jun@honbako.xyz") {
                Link(destination: supportURL) {
                    LabeledContent {
                        Text(verbatim: "jun@honbako.xyz")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("Support Email", systemImage: "envelope")
                    }
                }
                .accessibilityIdentifier("Honbako.Settings.SupportEmail")
            }
            if let profileURL = URL(string: "https://x.com/nsjunxiu") {
                Link(destination: profileURL) {
                    LabeledContent {
                        Text(verbatim: "@nsjunxiu")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("X", systemImage: "at")
                    }
                }
                .accessibilityIdentifier("Honbako.Settings.X")
            }
        } header: {
            Text("Honbako")
        } footer: {
            Text("Created by @nsjunxiu")
                .accessibilityIdentifier("Honbako.Settings.Creator")
        }
    }
}
#endif
