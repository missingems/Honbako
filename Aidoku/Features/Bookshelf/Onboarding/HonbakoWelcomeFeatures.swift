#if SUMI
import SwiftUI

struct HonbakoWelcomeFeatures: View {
    let page: HonbakoWelcomePage

    var body: some View {
        if page == .library {
            Section("Your Collection") {
                feature("Files", symbol: "folder", detail: "Import CBZ or ZIP comics from iCloud Drive or On My iPhone.")
                feature("Personal Servers", symbol: "externaldrive", detail: "Connect Komga, Kavita, or Suwayomi.")
                #if HONBAKO_EXTERNAL_SOURCES
                feature("Extensions", symbol: "puzzlepiece.extension", detail: "Add an extension repository, then install extensions for the manga sources you use.")
                #endif
                feature("iCloud Sync", symbol: "icloud", detail: "Keep your library, bookmarks, and reading progress in sync. Included for everyone.")
            }
        } else {
            Section("Connect Your Own AI Provider") {
                feature("Know your library", symbol: "books.vertical",
                        detail: "Share your manga, current chapter and page, and saved reading history with your companion.")
                #if HONBAKO_EXTERNAL_SOURCES
                feature("Find manga and manage sources", symbol: "magnifyingglass",
                        detail: "Search connected catalogs, add books, and request changes to sources and extension repositories for your approval.")
                #else
                feature("Find manga and manage sources", symbol: "magnifyingglass",
                        detail: "Search your connected collections, add books, and request source changes for your approval.")
                #endif
                feature("Explain and annotate pages", symbol: "pencil.tip.crop.circle",
                        detail: "Let your AI see the current page, explain a scene, or draw helpful annotations over it.")
                feature("Get a recap", symbol: "text.alignleft",
                        detail: "Ask your companion to recap what you have read without reading ahead.")
            }
            Section("Learn While Reading") {
                feature("Japanese readings and pronunciation", symbol: "character.book.closed",
                        detail: "See word-by-word readings on Japanese pages. Tap a word to listen or translate.")
            }
            Section {
                Text("Use your own AI subscription. Choose what your AI can access in MCP Server settings. Private reading is never shared.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func feature(_ title: LocalizedStringKey, symbol: String, detail: LocalizedStringKey) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}
#endif
