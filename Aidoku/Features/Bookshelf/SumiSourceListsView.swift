#if SUMI
import SwiftUI

struct SumiSourceListsView: View {
    @State private var urls: [URL] = []
    @State private var lists: [URL: SourceList] = [:]
    @State private var loading = false
    @State private var adding = false

    var body: some View {
        List {
            if urls.isEmpty {
                ContentUnavailableView {
                    Label("No Source Lists", systemImage: "link")
                } description: {
                    Text("Add the link supplied by your source provider, then choose which sources to connect.")
                } actions: {
                    Button("Add Source List") { adding = true }
                }
            } else {
                Section {
                    ForEach(urls, id: \.self) { url in
                        Group {
                            if let list = lists[url] {
                                NavigationLink { SumiSourceListCatalogView(list: list) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(list.name)
                                        Text(url.host ?? url.absoluteString).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(url.host ?? url.absoluteString)
                                    Text(loading ? "Loading…" : "Couldn’t load this list")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                Task {
                                    await SourceManager.shared.removeSourceList(url: url)
                                    await reload(fetch: false)
                                }
                            }
                        }
                    }
                } footer: { Text("Open a list to choose sources. Adding a list does not install its sources.") }
            }
        }
        .navigationTitle("Source Lists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if loading { ProgressView() }
                else if !urls.isEmpty { Button("Refresh", systemImage: "arrow.clockwise") { Task { await reload(fetch: true) } } }
                Button("Add Source List", systemImage: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) {
            SumiAddSourceListView { await reload(fetch: false) }
        }
        .task { await reload(fetch: true) }
    }

    private func reload(fetch: Bool) async {
        urls = await SourceManager.shared.getSourceListURLs().sorted { $0.absoluteString < $1.absoluteString }
        if fetch, !urls.isEmpty {
            loading = true
            await SourceManager.shared.startSourceListsReload()
            await SourceManager.shared.waitForSourceListsLoad()
            loading = false
        }
        lists = await SourceManager.shared.getLoadedSourceLists()
    }
}
#endif
