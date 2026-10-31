#if SUMI && HONBAKO_EXTERNAL_SOURCES
import SwiftUI

struct SumiExtensionsView: View {
    let importExtension: () -> Void
    @State private var repositoryCount: Int?

    var body: some View {
        List {
            Group {
                Section {
                    NavigationLink {
                        SumiSourceListsView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Extension repositories")
                                Text(repositoryCount == 0
                                     ? "No repositories yet. Tap to add."
                                     : "Add and manage extension repositories.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "puzzlepiece.extension") }
                    }
                    .accessibilityIdentifier("Honbako.Extensions.Repositories")
                    Button("Install extension file", systemImage: "square.and.arrow.down", action: importExtension)
                } footer: {
                    Text("Extensions provide manga sources. Add a repository to find and install compatible extensions.")
                }
            }
            .honbakoPaperRows()
        }
        .honbakoPaperListBackground()
        .navigationTitle("Extensions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await updateRepositoryCount() }
        .onReceive(NotificationCenter.default.publisher(for: .updateSourceList)) { _ in
            Task { await updateRepositoryCount() }
        }
    }

    private func updateRepositoryCount() async {
        repositoryCount = await SourceManager.shared.getSourceListURLs().count
    }
}
#endif
