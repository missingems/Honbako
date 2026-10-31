#if SUMI
import SwiftUI
#if HONBAKO_EXTERNAL_SOURCES
import UniformTypeIdentifiers
#endif

/// Connections are added deliberately. Search uses only enabled connections.
struct SumiSourcesView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HonbakoGuideLibrary.searchEnabledKey) private var searchGuides = true
    @State private var sources: [SourceInfo] = []
    @State private var changing: Set<String> = []
    @State private var importing = false
    @State private var errorMessage: String?
    @State private var proPresented = false
    @State private var proFeature: HonbakoProFeature?
    @ObservedObject private var pro = HonbakoProStore.shared
    @ObservedObject private var automation = HonbakoAutomationService.shared
    @AppStorage(HonbakoCoverDisplayPreferences.showCoverKey) private var showMangaCover = false
    @State private var localImportPresented = false
    @State private var preparingLocalImport = false

    var body: some View {
        NavigationStack {
            List {
                Group {
                    if HonbakoDeviceModel.isPhoneDuo {
                        Section {
                            Toggle("Show Manga Cover", isOn: Binding(get: { showMangaCover && pro.hasPro }, set: { enabled in
                                if enabled && !pro.hasPro { proFeature = .coverDisplay; proPresented = true }
                                else { showMangaCover = enabled }
                            }))
                                .accessibilityIdentifier("Honbako.Settings.ShowMangaCover")
                        } header: { Text("Cover Display") }
                        footer: {
                            Text("This is the default for your library. Each manga can override it from its Cover Mode menu. Showing the cover on iPhone Duo uses the camera while you read. No photos or video are recorded or saved.")
                        }
                    }

                    Section {
                        Toggle("On This Device", isOn: $searchGuides)
                            .accessibilityIdentifier("Honbako.Settings.SearchGuides")
                        ForEach(sources, id: \.sourceId) { source in
                            Toggle(isOn: Binding(
                                get: { !source.disabled },
                                set: { enabled in change(source, enabled: enabled) }
                            )) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.name)
                                    Text(source.languages.map(SourceLanguage.displayName).joined(separator: ", "))
                                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            .disabled(changing.contains(source.sourceId))
                        }
                    } header: { Text("Included in Search") }
                    footer: { Text("Connections provide the books you can find in Honbako.") }

                    Section {
                        Button(action: presentLocalImporter) {
                            Label("Import from Files", systemImage: "folder")
                        }
                        .disabled(preparingLocalImport)
                        .accessibilityIdentifier("Honbako.Settings.ImportFromFiles")
                        NavigationLink { SumiPersonalLibrariesView() } label: {
                            Label("Personal Server", systemImage: "externaldrive")
                        }
                    } header: { Text("Your Content") }
                    footer: { Text("Choose CBZ or ZIP comics from Files, including iCloud Drive and On My iPhone.") }

                    #if HONBAKO_EXTERNAL_SOURCES
                    Section {
                        NavigationLink {
                            SumiExtensionsView(importExtension: { importing = true })
                        } label: {
                            Label("Extensions", systemImage: "puzzlepiece.extension")
                        }
                        .accessibilityIdentifier("Honbako.Settings.Extensions")
                    }

                    #endif

                    Section {
                        NavigationLink {
                            HonbakoAutomationSettingsView()
                        } label: {
                            Label(automation.isEnabled ? "MCP Server" : "Turn On MCP Server", systemImage: "point.3.connected.trianglepath.dotted")
                                .badge(automation.pendingApprovals.count)
                        }
                        .accessibilityIdentifier("Honbako.Automation")
                    }

                    Section {
                        Button { proFeature = nil; proPresented = true } label: {
                            Label(pro.hasPro ? "Manage Subscription" : "Honbako Pro", systemImage: "star.circle")
                        }
                        NavigationLink { SumiCloudSyncView() } label: { Label("iCloud Sync", systemImage: "icloud") }
                    }

                    HonbakoContactSection()
                }
                .honbakoPaperRows()
            }
            .honbakoPaperListBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $proPresented) { HonbakoProView(feature: proFeature) }
            .sheet(isPresented: $localImportPresented) { LocalFileImportView() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                }
            }
            .task { await reload() }
            .onReceive(NotificationCenter.default.publisher(for: .sourceLoaded)) { _ in Task { await reload() } }
            .onReceive(NotificationCenter.default.publisher(for: .updateSourceList)) { _ in Task { await reload() } }
        }
        .tint(HonbakoPalette.accent)
        #if HONBAKO_EXTERNAL_SOURCES
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "aix") ?? .zip]) { result in
            switch result {
            case let .success(url):
                Task {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if await SourceManager.shared.importSource(from: url) == nil {
                        errorMessage = String(localized: "This extension couldn’t be installed. Choose a compatible .aix file and try again.")
                    }
                    await reload()
                }
            case let .failure(error): errorMessage = error.localizedDescription
            }
        }
        #endif
        .alert("Connection Unavailable", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func presentLocalImporter() {
        guard !preparingLocalImport else { return }
        preparingLocalImport = true
        Task { @MainActor in
            defer { preparingLocalImport = false }
            if !sources.contains(where: { $0.sourceId == LocalSourceRunner.sourceKey }) {
                guard await SourceManager.shared.createCustomSource(.local) != nil else {
                    errorMessage = String(localized: "Couldn’t prepare file import. Try again.")
                    return
                }
                await reload()
            }
            localImportPresented = true
        }
    }

    private func reload() async {
        await SumiCatalogBootstrap.shared.prepare()
        sources = await SourceManager.shared.getSourceInfos()
    }

    private func change(_ source: SourceInfo, enabled: Bool) {
        guard changing.insert(source.sourceId).inserted else { return }
        Task {
            if enabled {
                await SourceManager.shared.enable(sourceKey: source.sourceId)
                if await SourceManager.shared.source(for: source.sourceId) == nil {
                    await SourceManager.shared.disable(sourceKey: source.sourceId)
                    errorMessage = String(localized: "This source couldn’t be enabled. Import a current version and try again.")
                }
            } else { await SourceManager.shared.disable(sourceKey: source.sourceId) }
            await reload()
            changing.remove(source.sourceId)
        }
    }
}
#endif
