#if SUMI
import SwiftUI

struct SumiSourceListCatalogView: View {
    let list: SourceList
    @State private var installed: Set<String> = []
    @State private var query = ""
    @State private var loaded = false

    private var available: [SourceInfo] {
        var seen: Set<String> = []
        return list.sources.filter { entry in
            guard seen.insert(entry.id).inserted, !installed.contains(entry.id) else { return false }
            guard entry.nativeRunner == nil || entry.isNativeInstallable else { return false }
            guard SourcePackageCompatibility.supports(minimum: entry.minAppVersion,
                maximum: entry.maxAppVersion) else { return false }
            return true
        }.map { $0.toInfo() }
            .filter { query.isEmpty || $0.name.localizedStandardContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Group {
                if !loaded { ProgressView() }
                else if available.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView("No available extensions", systemImage: "checkmark.circle",
                            description: Text("There are no compatible extensions to install from this repository. Installed sources are available in Search."))
                    } else { ContentUnavailableView.search(text: query) }
                } else {
                    ForEach(available, id: \.sourceId) { source in
                        ExternalSourceTableCell(source: source, installTitleKey: "Install", onInstall: { Task { await reload() } })
                    }
                }
            }
            .honbakoPaperRows()
        }
        .honbakoPaperListBackground()
        .searchable(text: $query, prompt: "Find an extension")
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
