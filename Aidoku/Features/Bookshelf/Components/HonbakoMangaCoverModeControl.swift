#if SUMI
import SwiftUI

/// An override changes only this edition; the library preference stays intact.
struct HonbakoMangaCoverModeControl: View {
    let mangaID: MangaIdentifier
    let requestPro: () -> Void
    @ObservedObject private var pro = HonbakoProStore.shared
    @State private var mode: HonbakoCoverDisplayPreferences.MangaMode = .libraryDefault

    var body: some View {
        Menu {
            ForEach(HonbakoCoverDisplayPreferences.MangaMode.allCases) { choice in
                Button {
                    guard choice != .enabled || pro.hasPro else { requestPro(); return }
                    HonbakoCoverDisplayPreferences.setMangaMode(choice, for: mangaID)
                    mode = choice
                } label: {
                    if mode == choice { Label(choice.title, systemImage: "checkmark") }
                    else { Text(choice.title) }
                }
            }
        } label: {
            HStack {
                Label("Cover Mode", systemImage: "book.closed")
                Spacer(minLength: 8)
                Text(mode.title).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityIdentifier("Honbako.Manga.CoverMode")
        .accessibilityLabel("Cover Mode: \(mode.title)")
        .onAppear { mode = HonbakoCoverDisplayPreferences.mangaMode(for: mangaID) }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            mode = HonbakoCoverDisplayPreferences.mangaMode(for: mangaID)
        }
    }
}
#endif
