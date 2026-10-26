#if SUMI
import Foundation

@MainActor
final class HonbakoChapterAlerts {
    static let shared = HonbakoChapterAlerts()
    private var observer: NSObjectProtocol?

    nonisolated static func preferenceEnabled(for id: MangaIdentifier, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key(id)) as? Bool ?? true
    }

    nonisolated static func setPreference(_ enabled: Bool, for id: MangaIdentifier, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key(id))
    }

    nonisolated private static func key(_ id: MangaIdentifier) -> String {
        "Honbako.Notifications." + Data(id.sourceKey.utf8).base64EncodedString()
            + "." + Data(id.mangaKey.utf8).base64EncodedString()
    }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: HonbakoProStore.entitlementChangedNotification,
            object: nil, queue: .main) { _ in
                Task { @MainActor in await HonbakoChapterAlerts.shared.updateAvailability() }
            }
        Task { await updateAvailability() }
    }

    func updateAvailability() async {
        let enabled = HonbakoProStore.shared.hasPro
        AppSettings.library.notifyNewChapters.set(enabled)
        if enabled {
            if AppSettings.library.updateInterval.get() == "never" { AppSettings.library.updateInterval.set("daily") }
            await MangaManager.shared.scheduleLibraryRefresh()
            await NotificationManager.shared.deliverPendingNotifications()
        } else { await NotificationManager.shared.clearPendingNotifications() }
    }

    func didAddToLibrary(_ id: MangaIdentifier) async {
        // Opt each new saved title in, while respecting a previous explicit opt-out.
        if UserDefaults.standard.object(forKey: Self.key(id)) == nil {
            Self.setPreference(true, for: id)
        }
        guard HonbakoProStore.shared.hasPro, Self.preferenceEnabled(for: id) else { return }
        _ = await NotificationManager.shared.requestAuthorization()
        await updateAvailability()
    }

    func setEnabled(_ enabled: Bool, for id: MangaIdentifier) async {
        Self.setPreference(enabled, for: id)
        if enabled, HonbakoProStore.shared.hasPro { _ = await NotificationManager.shared.requestAuthorization() }
        await updateAvailability()
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
#endif
