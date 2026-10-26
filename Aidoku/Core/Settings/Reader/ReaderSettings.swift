//
//  ReaderSettings.swift
//  Aidoku
//
//  Created by skitty on 8/29/26.
//

struct ReaderSettings: Sendable {
    var keys: [any SettingsDefault] {
        [
            autoScrollPosition,
            upscaleQuality,
            pageSizing,
            paperTexture,
            paperTextureStrength
        ]
    }

    // todo: move reader settings here

    let autoScrollPosition = SettingsKey<AutoScrollPosition>("Reader.autoScrollPosition", default: .right)
    let upscaleQuality = SettingsKey<UpscaleQuality>("Reader.upscaleQuality", default: .fast)
    let pageSizing = SettingsKey<ReaderPageSizing>("Reader.pageSizing", default: .fit)
    let paperTexture = SettingsKey<Bool>("Reader.paperTexture", default: false)
    let paperTextureStrength = SettingsKey<ReaderPaperTextureStrength>("Reader.paperTextureStrength", default: .strong)
}
