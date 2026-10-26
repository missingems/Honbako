//
//  FlagSettings.swift
//  Aidoku
//
//  Created by skitty on 8/18/26.
//

struct FlagSettings: Sendable {
    var keys: [any SettingsDefault] {
        [
            currentVersion,
            isSideloaded,
            isiCloudAvailable,
            showedLegacySourceListNotice,
            starterSourceListConfigured,
            installedStarterSources,
            libraryRefreshInProgress,
            downloadChapterSortAscending,
            dismissedDictionaryInfo
        ]
    }

    let currentVersion = SettingsKey<String?>("Flag.currentVersion")
    let isSideloaded = SettingsKey<Bool>("Flag.isSideloaded", default: AppDelegate.isSideloaded)
    let isiCloudAvailable = SettingsKey<Bool>("Flag.isiCloudAvailable", default: false)
    let showedLegacySourceListNotice = SettingsKey<Bool>("Flag.showedLegacySourceListNotice", default: false)
    let starterSourceListConfigured = SettingsKey<Bool>("Flag.starterSourceListConfigured", default: false)
    let installedStarterSources = SettingsKey<Set<String>>("Flag.installedStarterSources", default: [])
    let libraryRefreshInProgress = SettingsKey<Bool>("Flag.libraryRefreshInProgress", default: false)
    let downloadChapterSortAscending = SettingsKey<Bool>("Flag.downloadChapterSortAscending", default: false)
    let dismissedDictionaryInfo = SettingsKey<Bool>("Flag.dismissedDictionaryInfo", default: false)
}
