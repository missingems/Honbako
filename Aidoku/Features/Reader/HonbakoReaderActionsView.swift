#if SUMI
import AidokuRunner
import SwiftUI

struct HonbakoReaderActionsView: View {
    @StateObject private var model: HonbakoReaderActionsModel
    @ObservedObject private var pro = HonbakoProStore.shared
    @State private var requestedPro: HonbakoProFeature?
    @State private var removingDownloads = false
    let sourceAvailable: Bool

    init(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter,
         chapters: [AidokuRunner.Chapter], sourceAvailable: Bool) {
        _model = StateObject(wrappedValue: HonbakoReaderActionsModel(manga: manga, chapter: chapter, chapters: chapters))
        self.sourceAvailable = sourceAvailable
    }

    var body: some View {
        Section {
            Button(model.isInLibrary ? "Remove from Library" : "Add to Library",
                   systemImage: model.isInLibrary ? "minus.circle" : "plus.circle") {
                Task { await model.toggleLibrary() }
            }
            .disabled(model.busy)
            .accessibilityIdentifier("Honbako.Reader.Library")
            Menu {
                Button("Download This Chapter", systemImage: "arrow.down.circle") { download(all: false) }
                    .disabled(!sourceAvailable || model.chapter.locked)
                Button("Download All Chapters", systemImage: "arrow.down.to.line") { download(all: true) }
                    .disabled(!sourceAvailable)
                if model.hasDownloads {
                    Button("Remove Offline Copies", systemImage: "trash", role: .destructive) { removingDownloads = true }
                }
            } label: { Label("Offline Reading", systemImage: "arrow.down.circle") }
            .disabled(model.busy)
            .accessibilityIdentifier("Honbako.Reader.Offline")
            Button {
                guard pro.hasPro else { requestedPro = .chapterAlerts; return }
                Task { await model.setNotifications(!model.notificationsEnabled || !model.notificationsAuthorized) }
            } label: {
                HStack {
                    Label("New Chapter Notifications", systemImage: model.notificationsEnabled ? "bell.badge" : "bell.slash")
                    Spacer()
                    Text(pro.hasPro ? (model.notificationsEnabled ? (model.notificationsAuthorized ? "On" : "Allow") : "Off") : "Pro")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!model.isInLibrary || model.busy)
            .accessibilityIdentifier("Honbako.Reader.Notify")
            if let message = model.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        } footer: {
            Text("Downloads require permission from the source. Chapter alerts use iOS background refresh, so their timing can vary.")
        }
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .updateLibrary)) { _ in Task { await model.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .downloadsRemoved)) { _ in Task { await model.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .downloadRemoved)) { _ in Task { await model.refresh() } }
        .sheet(item: $requestedPro) { feature in HonbakoProView(feature: feature) }
        .confirmationDialog("Remove offline copies?", isPresented: $removingDownloads, titleVisibility: .visible) {
            Button("Remove Downloads", role: .destructive) { Task { await model.removeDownloads() } }
        } message: { Text("Your library and reading progress will be kept.") }
    }

    private func download(all: Bool) {
        guard pro.hasPro else { requestedPro = .offline; return }
        Task { await model.download(all: all) }
    }
}
#endif
