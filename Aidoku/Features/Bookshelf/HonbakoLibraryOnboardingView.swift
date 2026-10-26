#if SUMI
import SwiftUI

struct HonbakoLibraryOnboardingView: View {
    let localFilesAdded: Bool
    let importSource: () -> Void

    var body: some View {
        List {
            Section {
                NavigationLink { LocalSetupView() } label: {
                    Label("Local Files", systemImage: "folder")
                }
                .disabled(localFilesAdded)
                NavigationLink { SumiPersonalLibrariesView() } label: {
                    Label("Personal Server", systemImage: "externaldrive")
                }
                NavigationLink { SumiSourceListsView() } label: {
                    Label("Source Lists", systemImage: "link")
                }
                Button("Import Source File", systemImage: "square.and.arrow.down", action: importSource)
            } header: {
                Text("1. Choose a Connection")
            } footer: {
                Text("Add your own files, connect a personal server, or choose a source list or source file you trust. Honbako includes no source lists or manga.")
            }

            Section("2. Find Manga") {
                Text("Return to your library and pull down to search. Search uses the connections you enable in Settings.")
            }

            Section("3. Build Your Library") {
                Text("Choose Add next to a search result to keep it in your library. Choose Read or Resume to start reading.")
            }

        }
        .navigationTitle("Getting Started")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("Honbako.Settings.GettingStarted")
    }
}
#endif
