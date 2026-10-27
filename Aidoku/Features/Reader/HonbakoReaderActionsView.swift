#if SUMI
import AidokuRunner
import SwiftUI

struct HonbakoReaderActionsView: View {
    @StateObject private var model: HonbakoReaderActionsModel
    @ObservedObject private var pro = HonbakoProStore.shared
    @ObservedObject var chapterState: HonbakoReaderChapterState
    @State private var removingDownloads = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    let sourceAvailable: Bool
    let requestPro: (HonbakoProFeature) -> Void

    init(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter,
         chapters: [AidokuRunner.Chapter], sourceAvailable: Bool,
         chapterState: HonbakoReaderChapterState, requestPro: @escaping (HonbakoProFeature) -> Void) {
        _model = StateObject(wrappedValue: HonbakoReaderActionsModel(manga: manga, chapter: chapter, chapters: chapters))
        self.sourceAvailable = sourceAvailable
        self.chapterState = chapterState
        self.requestPro = requestPro
    }

    private var isBundledTutorial: Bool { model.manga.sourceKey == HonbakoTutorialManga.sourceKey }

    var body: some View {
        Section {
            Button(model.isInLibrary ? String(localized: "Remove from Library") : String(localized: "Add to Library"),
                   systemImage: model.isInLibrary ? "minus.circle" : "plus.circle") {
                Task { await model.toggleLibrary() }
            }
            .disabled(model.busy)
            .accessibilityIdentifier("Honbako.Reader.Library")
            if isBundledTutorial {
                Label("Available Offline", systemImage: "checkmark.circle")
                    .accessibilityIdentifier("Honbako.Reader.BundledOffline")
            } else {
            Menu {
                Button("Download This Chapter", systemImage: "arrow.down.circle") { download(all: false) }
                    .disabled(!sourceAvailable || model.chapter.locked)
                Button("Download All Chapters", systemImage: "arrow.down.to.line") { download(all: true) }
                    .disabled(!sourceAvailable)
                if !chapterState.activeDownloads.isEmpty {
                    Button("Cancel Downloads", systemImage: "xmark.circle") { cancelDownloads() }
                }
                if chapterState.hasCopies || model.hasDownloads {
                    Button("Remove Offline Copies", systemImage: "trash", role: .destructive) { removingDownloads = true }
                }
            } label: { Label("Offline Reading", systemImage: "arrow.down.circle") }
            .disabled(model.busy)
            .accessibilityIdentifier("Honbako.Reader.Offline")
            }
            if !chapterState.activeDownloads.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(chapterState.activeDownloads.count == 1 ? String(localized: "Downloading Chapter")
                            : String(localized: "Downloading \(chapterState.activeDownloads.count) Chapters"))
                        Spacer()
                        Button("Cancel", action: cancelDownloads).buttonStyle(.borderless)
                    }
                    .font(.subheadline)
                    ProgressView(value: chapterState.progress ?? 0)
                        .accessibilityIdentifier("Honbako.Reader.DownloadProgress")
                }
            }
            if chapterState.failedCount > 0 {
                HStack {
                    Text(chapterState.failedCount == 1 ? String(localized: "Download Failed")
                        : String(localized: "\(chapterState.failedCount) Downloads Failed"))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") {
                        guard pro.hasPro else { requestPro(.offline); return }
                        let failed = model.chapters.filter { chapterState.statuses[$0.key] == .failed }
                        Task { await model.download(chosen: failed); await chapterState.refresh() }
                    }
                    .disabled(!sourceAvailable || model.busy)
                }
                .accessibilityIdentifier("Honbako.Reader.DownloadFailed")
            }
            if !isBundledTutorial {
            Button {
                guard model.isInLibrary else {
                    model.message = String(localized: "Add this manga to your library to enable chapter alerts.")
                    return
                }
                guard pro.hasPro else { requestPro(.chapterAlerts); return }
                Task { await model.setNotifications(!model.notificationsEnabled || !model.notificationsAuthorized) }
            } label: {
                HStack {
                    Label("New Chapter Notifications", systemImage: model.notificationsEnabled && model.notificationsAuthorized ? "bell.badge" : "bell.slash")
                    Spacer()
                    Text(notificationState).foregroundStyle(.secondary)
                }
            }
            .disabled(model.busy)
            .accessibilityIdentifier("Honbako.Reader.Notify")
            if model.notificationsDenied {
                Button("Open Notification Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .accessibilityIdentifier("Honbako.Reader.NotificationSettings")
            }
            }
            if let message = model.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        } footer: {
            if !isBundledTutorial {
                Text("Downloads require permission from the source. Chapter alerts use iOS background refresh, so their timing can vary.")
            }
        }
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .updateLibrary)) { _ in Task { await model.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: HonbakoProStore.entitlementChangedNotification)) { _ in Task { await model.refresh() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
        .confirmationDialog("Remove offline copies?", isPresented: $removingDownloads, titleVisibility: .visible) {
            Button("Remove Downloads", role: .destructive) { Task { await model.removeDownloads(); await chapterState.refresh() } }
        } message: { Text("Your library and reading progress will be kept.") }
    }

    private var notificationState: String {
        guard model.isInLibrary else { return String(localized: "Add First") }
        guard pro.hasPro else { return String(localized: "Pro") }
        guard model.notificationsEnabled else { return String(localized: "Off") }
        return model.notificationsAuthorized ? String(localized: "On") : String(localized: "Allow")
    }

    private func download(all: Bool) {
        guard pro.hasPro else { requestPro(.offline); return }
        Task { await model.download(all: all); await chapterState.refresh() }
    }

    private func cancelDownloads() {
        let identifiers = chapterState.activeDownloads.map(\.chapterIdentifier)
        Task { await DownloadManager.shared.cancelDownloads(for: identifiers); await chapterState.refresh() }
    }
}
#endif
