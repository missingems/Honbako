#if SUMI
import Foundation

/// Sumi has one adaptive reading experience, registered before opening its store.
enum SumiDefaults {
    static let freeSyncMigrationKey = "Honbako.iCloud.FreeSyncMigration.v1"

    static func register(in defaults: UserDefaults = .standard) {
        SumiLanguagePreferenceScope.removeAbandoned(in: defaults)
        // The previous release rewrote this preference from the Pro entitlement.
        // Migrate that gate once before the store opens; future launches respect
        // the reader's own sync choice.
        if !defaults.bool(forKey: freeSyncMigrationKey) {
            defaults.set(true, forKey: "General.icloudSync")
            defaults.set(true, forKey: freeSyncMigrationKey)
        }
        defaults.register(defaults: [
            HonbakoLibraryPreferences.hideFinishedBooksKey: false,
            "General.icloudSync": true,
            "Reader.pageSizing": "fit",
            "Reader.pagedPageLayout": "auto",
            "Reader.readingMode": "auto",
            "Reader.paperTexture": true,
            "Reader.paperTextureStrength": "medium",
            "Reader.pagesToPreload": 4,
            "Reader.tapZones": "disabled",
            "Reader.disableDoubleTap": true,
            "Reader.orientation": "device",
            "Reader.animatePageTransitions": true,
            "Reader.splitWideImages": false,
            "Reader.cropBorders": false,
            "Library.updateInterval": "daily"
        ])
    }
}
#endif
