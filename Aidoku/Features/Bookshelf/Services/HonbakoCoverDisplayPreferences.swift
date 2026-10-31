#if SUMI
import Foundation

enum HonbakoCoverDisplayPreferences {
    static let showCoverKey = "Honbako.Reader.ShowCoverDisplay"

    enum MangaMode: String, CaseIterable, Identifiable {
        case libraryDefault, enabled, disabled
        var id: Self { self }
        var title: String {
            switch self {
            case .libraryDefault: String(localized: "Use Library Setting")
            case .enabled: String(localized: "On for This Manga")
            case .disabled: String(localized: "Off for This Manga")
            }
        }
    }

    static func showCover(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: showCoverKey) as? Bool ?? false
    }

    static func mangaMode(for id: MangaIdentifier, in defaults: UserDefaults = .standard) -> MangaMode {
        guard let value = defaults.object(forKey: mangaKey(id)) as? Bool else { return .libraryDefault }
        return value ? .enabled : .disabled
    }

    static func setMangaMode(_ mode: MangaMode, for id: MangaIdentifier, in defaults: UserDefaults = .standard) {
        switch mode {
        case .libraryDefault: defaults.removeObject(forKey: mangaKey(id))
        case .enabled: defaults.set(true, forKey: mangaKey(id))
        case .disabled: defaults.set(false, forKey: mangaKey(id))
        }
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
    }

    static func showCover(for id: MangaIdentifier?, in defaults: UserDefaults = .standard) -> Bool {
        guard let id else { return showCover(in: defaults) }
        switch mangaMode(for: id, in: defaults) {
        case .libraryDefault: return showCover(in: defaults)
        case .enabled: return true
        case .disabled: return false
        }
    }

    private static func mangaKey(_ id: MangaIdentifier) -> String {
        "Honbako.Reader.MangaCover." + Data(id.sourceKey.utf8).base64EncodedString()
            + "." + Data(id.mangaKey.utf8).base64EncodedString()
    }
}
#endif
