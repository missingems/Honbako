#if SUMI
import SwiftUI

struct SumiSourceListCatalogView: View {
    let list: SourceList
    @State private var installed: Set<String> = []
    @State private var query = ""
    @State private var loaded = false

    private var available: [SourceInfo] {
        let version = SemanticVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")
        var seen: Set<String> = []
        return list.sources.filter { entry in
            guard seen.insert(entry.id).inserted, !installed.contains(entry.id) else { return false }
            if let minimum = entry.minAppVersion, SemanticVersion(minimum) > version { return false }
            if let maximum = entry.maxAppVersion, SemanticVersion(maximum) < version { return false }
            return true
        }.map { $0.toInfo() }
            .filter { query.isEmpty || $0.name.localizedStandardContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            if !loaded { ProgressView() }
            else if available.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("All Sources Added", systemImage: "checkmark.circle",
                        description: Text("Your connected sources are available in Search."))
                } else { ContentUnavailableView.search(text: query) }
            } else {
                ForEach(available, id: \.sourceId) { source in
                    ExternalSourceTableCell(source: source, onInstall: { Task { await reload() } })
                }
            }
        }
        .searchable(text: $query, prompt: "Find a source")
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private func reload() async {
        installed = Set(await SourceManager.shared.getSourceInfos().map(\.sourceId))
        loaded = true
    }
}
#endif
