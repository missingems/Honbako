#if SUMI
import SwiftUI

struct SumiSearchLanguageDetailsView: View {
    let info: SumiSearchLanguageInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(info.codes, id: \.self) { code in
                        Text(SourceLanguage.displayName(for: code))
                    }
                } footer: {
                    Text(info.scope == .chapters
                        ? String(localized: "Languages with known chapters for this title. Chapter coverage can vary.")
                        : String(localized: "Languages advertised by this source. Chapter languages for this title have not been confirmed."))
                }
            }
            .navigationTitle(info.scope == .chapters ? String(localized: "Chapter Languages") : String(localized: "Source Languages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(idealWidth: 340, idealHeight: 420)
        .presentationDetents([.medium, .large])
    }
}
#endif
