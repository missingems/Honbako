//
//  PageSizing.swift
//  Aidoku
//

import Foundation

enum ReaderPageSizing: String, SettingsValue, CaseIterable {
    case fit
    case fill

    var title: String {
        switch self {
            case .fit: NSLocalizedString("FIT_SCREEN")
            case .fill: NSLocalizedString("FILL_WIDTH")
        }
    }
}
