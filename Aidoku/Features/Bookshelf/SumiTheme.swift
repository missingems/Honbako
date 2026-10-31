#if SUMI
import SwiftUI
import UIKit

enum SumiTheme {
    static let paper = Color(uiColor: .systemBackground)
    static let ink = Color.primary
    static let secondaryInk = Color.secondary
    static var vermilion: Color { HonbakoPalette.accent }
    static let rule = Color(uiColor: .separator)
    static let accents: [Color] = [.blue, .orange, .green, .purple, .red]
}
#endif
