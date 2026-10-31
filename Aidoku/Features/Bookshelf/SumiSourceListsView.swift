#if SUMI
import SwiftUI

struct SumiSourceListsView: View {
    @State private var urls: [URL] = []
    @State private var lists: [URL: SourceList] = [:]
    @State private var loading = false
    @State private var adding = false

    var body: some View {
        List {
            Group {
                if urls.isEmpty {
                    ContentUnavailableView {
                        Label("No extension repositories", systemImage: "puzzlepiece.extension")
                    } description: {
                        Text("You haven’t added any extension repositories yet.")
                    } actions: {
                        Button("Add repository") { adding = true }
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
                                        Text(loading ? String(localized: "Loading…") : String(localized: "Couldn’t load this repository"))
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
                    } footer: { Text("Open a repository to browse extensions. Adding a repository does not install its extensions.") }
                }
            }
            .honbakoPaperRows()
        }
        .honbakoPaperListBackground()
        .navigationTitle("Extension repositories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if loading { ProgressView() }
                else if !urls.isEmpty { Button("Refresh", systemImage: "arrow.clockwise") { Task { await reload(fetch: true) } } }
                Button("Add repository", systemImage: "plus") { adding = true }
                    .accessibilityIdentifier("Honbako.Extensions.AddRepository")
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
