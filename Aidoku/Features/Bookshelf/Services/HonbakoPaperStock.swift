#if SUMI
import UIKit

/// Four small cached tiles share the reader's original fiber pattern. Rendering
/// a list never regenerates noise, downloads artwork, or processes a full screen.
enum HonbakoPaperStock {
    enum Surface { case page, card }

    private static let lightPage = make(dark: false, surface: .page)
    private static let lightCard = make(dark: false, surface: .card)
    private static let darkPage = make(dark: true, surface: .page)
    private static let darkCard = make(dark: true, surface: .card)

    static func tile(dark: Bool, surface: Surface) -> UIImage {
        switch (dark, surface) {
        case (false, .page): lightPage
        case (false, .card): lightCard
        case (true, .page): darkPage
        case (true, .card): darkCard
        }
    }

    static func base(dark: Bool, surface: Surface) -> UIColor {
        switch (dark, surface) {
        case (false, .page): UIColor(red: 0.961, green: 0.941, blue: 0.902, alpha: 1)
        case (false, .card): UIColor(red: 1, green: 0.988, blue: 0.965, alpha: 1)
        case (true, .page): UIColor(red: 0.090, green: 0.078, blue: 0.063, alpha: 1)
        case (true, .card): UIColor(red: 0.141, green: 0.125, blue: 0.102, alpha: 1)
        }
    }

    private static func make(dark: Bool, surface: Surface) -> UIImage {
        let grain = SumiPaperSurface.inkTile.withTintColor(dark ? .white : .black, renderingMode: .alwaysOriginal)
        let format = UIGraphicsImageRendererFormat()
        format.scale = grain.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: grain.size, format: format).image { context in
            base(dark: dark, surface: surface).setFill()
            context.fill(CGRect(origin: .zero, size: grain.size))
            grain.draw(at: .zero, blendMode: .normal, alpha: dark ? 0.42 : 0.6)
        }
    }
}
#endif
