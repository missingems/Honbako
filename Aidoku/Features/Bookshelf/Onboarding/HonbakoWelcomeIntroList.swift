#if SUMI
import SwiftUI

struct HonbakoWelcomeIntroList: View {
    let page: HonbakoWelcomePage

    var body: some View {
        List {
            Group {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(page.title)
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("Honbako.Welcome.Title")
                        Text(page.detail)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HonbakoWelcomeArtwork(page: page)
                        .frame(height: 132)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                HonbakoWelcomeFeatures(page: page)
            }
            .honbakoPaperRows()
        }
        .honbakoPaperListBackground()
        .listStyle(.insetGrouped)
        .navigationTitle(page.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
