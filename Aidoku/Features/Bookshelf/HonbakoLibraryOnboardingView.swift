#if SUMI
import SwiftUI

struct HonbakoLibraryOnboardingView: View {
    let localFilesAdded: Bool
    let importSource: () -> Void
    @State private var localImportPresented = false

    var body: some View {
        List {
            Group {
                Section {
                    #if HONBAKO_EXTERNAL_SOURCES
                    Text("Honbako.ExternalBeta.Intro")
                    #else
                    Text("Honbako.CollectionGuide.Intro.Body")
                    #endif
                } header: {
                    Text("Honbako.CollectionGuide.Intro.Title")
                }

                Section {
                    Text("Honbako.CollectionGuide.Local.Body")
                    if localFilesAdded {
                        Label("Honbako.CollectionGuide.Local.Connected", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        NavigationLink { LocalSetupView() } label: {
                            Label("Honbako.CollectionGuide.Local.Setup", systemImage: "folder.badge.plus")
                        }
                        .accessibilityIdentifier("Honbako.GettingStarted.LocalSetup")
                    }
                    Button("Honbako.CollectionGuide.Local.Import", systemImage: "square.and.arrow.down", action: presentLocalImporter)
                        .disabled(!localFilesAdded)
                        .accessibilityIdentifier("Honbako.GettingStarted.ImportComic")
                } header: {
                    Text("Honbako.CollectionGuide.Local.Title")
                } footer: {
                    Text("Honbako.CollectionGuide.Local.Footer")
                }

                Section {
                    Text("Honbako.CollectionGuide.Server.Body")
                    NavigationLink { SumiPersonalLibrariesView() } label: {
                        Label("Personal Server", systemImage: "externaldrive")
                    }
                    .accessibilityIdentifier("Honbako.GettingStarted.PersonalServer")
                } header: {
                    Text("Honbako.CollectionGuide.Server.Title")
                }

                #if HONBAKO_EXTERNAL_SOURCES
                Section {
                    Text("Honbako.CollectionGuide.Sources.Body")
                    NavigationLink { SumiExtensionsView(importExtension: importSource) } label: {
                        Label("Extensions", systemImage: "puzzlepiece.extension")
                    }
                    .accessibilityIdentifier("Honbako.GettingStarted.SourceLists")
                } header: {
                    Text("Honbako.CollectionGuide.Sources.Title")
                } footer: {
                    Text("Honbako.CollectionGuide.Sources.Footer")
                }
                #endif

                Section {
                    Text("Honbako.CollectionGuide.Search.Body")
                    Text("Honbako.CollectionGuide.Save.Body")
                } header: {
                    Text("Honbako.CollectionGuide.Search.Title")
                }
            }
            .honbakoPaperRows()
        }
        .honbakoPaperListBackground()
        .navigationTitle("Getting Started")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("Honbako.Settings.GettingStarted")
        .sheet(isPresented: $localImportPresented) { LocalFileImportView() }
    }

    private func presentLocalImporter() {
        localImportPresented = true
    }
}
#endif
