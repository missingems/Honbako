#if SUMI
import Foundation

/// Sumi has one adaptive reading experience, registered before opening its store.
enum SumiDefaults {
    static func register(in defaults: UserDefaults = .standard) {
        SumiLanguagePreferenceScope.removeAbandoned(in: defaults)
        // Configure the store before it opens. Only a previously verified Pro
        // entitlement can enable mirroring; fresh installations remain local.
        defaults.set(HonbakoProStore.cachedHasPro, forKey: "General.icloudSync")
        defaults.register(defaults: [
            "General.icloudSync": false,
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
