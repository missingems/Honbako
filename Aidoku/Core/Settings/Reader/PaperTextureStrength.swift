import Foundation

enum ReaderPaperTextureStrength: String, SettingsValue, CaseIterable {
    case light
    case medium
    case strong

    var title: String {
        switch self {
            case .light: NSLocalizedString("PAPER_TEXTURE_LIGHT")
            case .medium: NSLocalizedString("PAPER_TEXTURE_MEDIUM")
            case .strong: NSLocalizedString("PAPER_TEXTURE_STRONG")
        }
    }
}
