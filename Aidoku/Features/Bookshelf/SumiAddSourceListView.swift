#if SUMI
import SwiftUI

struct SumiAddSourceListView: View {
    let didAdd: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var adding = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private var url: URL? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else { return nil }
        return url
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        TextField("https://…", text: $address)
                            .textContentType(.URL).keyboardType(.URL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focused).disabled(adding)
                            .accessibilityIdentifier("Sumi.Sources.ListURL")
                    } header: { Text("Repository URL") }
                    footer: { Text("Enter a compatible extension repository URL. You’ll choose which extensions to install afterward.") }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
                }
                .honbakoPaperRows()
            }
            .honbakoPaperListBackground()
            .navigationTitle("Add repository")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(adding) }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let url, !adding else { return }
                        adding = true
                        Task {
                            if await SourceManager.shared.addSourceList(url: url) {
                                await didAdd()
                                dismiss()
                            } else { errorMessage = String(localized: "This repository couldn’t be added. Check the URL or try again.") }
                            adding = false
                        }
                    } label: {
                        if adding { ProgressView() } else { Text("Add") }
                    }
                    .disabled(url == nil || adding)
                }
            }
            .task { focused = true }
            .interactiveDismissDisabled(adding)
        }
        .tint(HonbakoPalette.accent)
    }
}
#endif
