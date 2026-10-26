#if SUMI
import SwiftUI
import UniformTypeIdentifiers

/// Connections are added deliberately. Search uses only enabled connections.
struct SumiSourcesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sources: [SourceInfo] = []
    @State private var changing: Set<String> = []
    @State private var importing = false
    @State private var errorMessage: String?
    @State private var proPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if sources.isEmpty {
                        Text("No connections yet").foregroundStyle(.secondary)
                    }
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

                Section("Your Content") {
                    NavigationLink { LocalSetupView() } label: {
                        Label("Local Files", systemImage: "folder")
                    }
                    .disabled(sources.contains { $0.sourceId == LocalSourceRunner.sourceKey })
                    NavigationLink { SumiPersonalLibrariesView() } label: {
                        Label("Personal Server", systemImage: "externaldrive")
                    }
                }
                Section {
                    NavigationLink { SumiSourceListsView() } label: {
                        Label("Source Lists", systemImage: "link")
                    }
                    Button("Import Source File", systemImage: "square.and.arrow.down") { importing = true }
                } header: { Text("More Sources") }
                footer: { Text("Add a source list supplied by your provider, or import a source file you trust. Honbako includes no source lists or manga.") }

                Section {
                    Button { proPresented = true } label: {
                        Label("Honbako Pro", systemImage: "star.circle")
                    }
                    NavigationLink { SumiCloudSyncView() } label: { Label("iCloud Sync", systemImage: "icloud") }
                }
            }
            .navigationTitle("Connections")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $proPresented) { HonbakoProView(feature: nil) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                }
            }
            .task { await reload() }
            .onReceive(NotificationCenter.default.publisher(for: .sourceLoaded)) { _ in Task { await reload() } }
            .onReceive(NotificationCenter.default.publisher(for: .updateSourceList)) { _ in Task { await reload() } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "aix") ?? .zip]) { result in
                switch result {
                case let .success(url):
                    Task {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        if await SourceManager.shared.importSource(from: url) == nil {
                            errorMessage = "This source couldn’t be imported. Choose a compatible .aix file and try again."
                        }
                        await reload()
                    }
                case let .failure(error): errorMessage = error.localizedDescription
                }
            }
            .alert("Connection Unavailable", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .tint(.primary)
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
                    errorMessage = "This source couldn’t be enabled. Import a current version and try again."
                }
            } else { await SourceManager.shared.disable(sourceKey: source.sourceId) }
            await reload()
            changing.remove(source.sourceId)
        }
    }
}
#endif
