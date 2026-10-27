#if SUMI
import Foundation

enum HonbakoCoverDisplayPreferences {
    static let showCoverKey = "Honbako.Reader.ShowCoverDisplay"

    static func showCover(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: showCoverKey) as? Bool ?? true
    }
}
#endif
