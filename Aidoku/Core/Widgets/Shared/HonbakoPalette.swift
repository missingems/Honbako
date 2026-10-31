#if SUMI || HONBAKO_WIDGET_EXTENSION
import SwiftUI
import UIKit

/// One semantic dune palette for the app, illustrations, and widget extension.
/// Constants also work in the extension, which doesn't bundle the app's assets.
enum HonbakoPalette {
    static let accentUIColor = UIColor { traits in
        if traits.accessibilityContrast == .high {
            return color(traits.userInterfaceStyle == .dark ? 0xE6CDA8 : 0x674B2F)
        }
        return color(traits.userInterfaceStyle == .dark ? 0xCBAA80 : 0x806344)
    }

    static var accent: Color { Color(uiColor: accentUIColor) }

    // White action labels retain at least 4.5:1 contrast in both appearances.
    // The lighter dark-mode accent is reserved for links, symbols, and toggles.
    static let actionUIColor = UIColor { traits in
        color(traits.accessibilityContrast == .high ? 0x674B2F : 0x806344)
    }
    static var action: Color { Color(uiColor: actionUIColor) }
    static let onAction = Color.white

    /// A deeper dune keeps the reader rail legible over bright manga pages.
    static let scrubberUIColor = UIColor { traits in
        color(traits.accessibilityContrast == .high ? 0x50391F : 0x674B2F)
    }

    /// Tint the glass itself; the page thumbnails and symbols stay fully opaque.
    static let glassTintOpacity: CGFloat = 0.619
    static let glassTintUIColor = UIColor { traits in
        scrubberUIColor.resolvedColor(with: traits)
            .withAlphaComponent(traits.accessibilityContrast == .high ? 1 : glassTintOpacity)
    }
    static var glassTint: Color { Color(uiColor: glassTintUIColor) }

    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif
