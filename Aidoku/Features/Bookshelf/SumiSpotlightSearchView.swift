#if SUMI
import AidokuRunner
import SwiftUI

struct SumiSpotlightSearchView: View {
    @ObservedObject var store: SumiLibraryStore
    @ObservedObject var presentation: SumiSearchPresentation
    @ObservedObject var opening: SumiGridOpeningState
    let previewBooks: [SumiBook]?
    let recommendations: [SumiBook]
    let openBook: (SumiBook, SumiBookTransitionSource?) -> Void
    let dismiss: () -> Void
    @State private var sourcesPresented = false
    @State private var previewLibraryIDs: Set<MangaIdentifier> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var query: String { presentation.query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var books: [SumiBook] {
        if let previewBooks {
            return query.isEmpty ? Array(previewBooks.prefix(6))
                : previewBooks.filter { $0.title.localizedStandardContains(query) }
        }
        let recent = store.recentlyRead.isEmpty ? store.library : store.recentlyRead
        return query.isEmpty ? Array(recent.prefix(6)) : store.searchResults
    }

    var body: some View {
        GeometryReader { geometry in
            let results = books
            let region = availableRegion(geometry)
            let width = max(1, min(620, region.width - 24))
            let top = region.minY + min(60, max(12, region.height * 0.08))
            ZStack(alignment: .topLeading) {
                Button(action: dismiss) { Color.black.opacity(0.18).ignoresSafeArea() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close Search")
                    .accessibilityIdentifier("Sumi.Search.Dismiss")
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        SumiSpotlightSearchField(text: $presentation.query,
                            isActive: presentation.isPresented && !sourcesPresented, dismiss: dismiss)
                            .frame(minHeight: 52)
                        Button { sourcesPresented = true } label: {
                            Label("Connections", systemImage: "link")
                                .labelStyle(.iconOnly)
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("Sumi.Search.Sources")
                    }
                    .padding(.horizontal, 12)
                    if !results.isEmpty || !query.isEmpty {
                        Divider()
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(results) { book in
                                    SumiSpotlightResultRow(book: book,
                                        isLifted: opening.bookID == book.presentation.id,
                                        isInLibrary: book.isInLibrary || previewLibraryIDs.contains(book.id),
                                        isSearchActive: presentation.isPresented,
                                        editions: store.editions(for: book), sourceName: store.sourceName(for:),
                                        openBook: openBook, addBook: { book in
                                            if previewBooks != nil { previewLibraryIDs.insert(book.id) }
                                            else { await store.add(book: book) }
                                        }, showsDivider: book.id != results.last?.id)
                                }
                                if store.isSearching, previewBooks == nil {
                                    ProgressView().padding(16).accessibilityLabel("Searching")
                                } else if results.isEmpty, !query.isEmpty {
                                    if store.needsConnection, previewBooks == nil {
                                        ContentUnavailableView {
                                            Label("Connect a Library", systemImage: "link")
                                        } description: {
                                            Text("Add your files, a personal server, or a source to search.")
                                        } actions: {
                                            Button("Connections") { sourcesPresented = true }
                                        }
                                    } else if let error = store.errorMessage, previewBooks == nil {
                                        ContentUnavailableView {
                                            Label("Search unavailable", systemImage: "wifi.exclamationmark")
                                        } description: { Text(error) }
                                        actions: { Button("Try Again") { store.search(query: query) } }
                                    } else {
                                        ContentUnavailableView.search(text: query)
                                    }
                                }
                            }
                            .padding(8)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .frame(maxHeight: max(80, region.maxY - top - 80))
                    } else if previewBooks == nil {
                        Divider()
                        HStack {
                            Text("Connect a library to search.").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Button("Add Connection") { sourcesPresented = true }
                                .buttonStyle(.bordered)
                        }
                        .padding(16)
                    }
                }
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .shadow(color: .black.opacity(0.14), radius: 24, y: 10)
                .offset(x: region.midX - width / 2,
                        y: top - (reduceMotion ? 0 : 24 * (1 - presentation.revealProgress)))
            }
        }
        .tint(.primary)
        .sheet(isPresented: $sourcesPresented) { SumiSourcesView() }
        .onChange(of: presentation.query) { search() }
        .onChange(of: presentation.isPresented) { if presentation.isPresented { search() } }
        .onChange(of: sourcesPresented) { if !sourcesPresented, !query.isEmpty { search() } }
        .onAppear { search() }
    }

    private func availableRegion(_ geometry: GeometryProxy) -> CGRect {
        let bounds = CGRect(origin: .zero, size: geometry.size)
        guard #available(iOS 27.1, *) else { return bounds }
        let exclusions = (geometry.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
            + geometry.reservedRegions(kind: .occlusion, layoutDirectionBehavior: .fixed))
            .filter(\.isActive).map(\.frame)
        return ReaderControlLayout.availableRegions(in: bounds, avoiding: exclusions)
            .filter { $0.width >= 180 && $0.height >= 100 }
            .max { lhs, rhs in
                let difference = lhs.width * lhs.height - rhs.width * rhs.height
                return abs(difference) > 1 ? difference < 0 : lhs.maxX < rhs.maxX
            } ?? bounds
    }

    private func search() {
        guard presentation.isPresented, previewBooks == nil else { return }
        if query.isEmpty { store.cancelSearch() }
        else { store.search(query: query) }
    }
}
#endif
