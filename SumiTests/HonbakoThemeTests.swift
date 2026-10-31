@testable import Sumi
import UIKit
import Testing

@MainActor
struct HonbakoThemeTests {
    @Test("Dune links adapt to light, dark, and increased-contrast appearances")
    func adaptiveDuneAccent() throws {
        for (style, contrast, expected) in variants {
            let traits = UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: style),
                UITraitCollection(accessibilityContrast: contrast)
            ])
            let resolved = HonbakoPalette.accentUIColor.resolvedColor(with: traits)
            let channels = try rgb(resolved)
            #expect(abs(channels.red - CGFloat((expected >> 16) & 255) / 255) < 0.0001)
            #expect(abs(channels.green - CGFloat((expected >> 8) & 255) / 255) < 0.0001)
            #expect(abs(channels.blue - CGFloat(expected & 255) / 255) < 0.0001)

            // The app's global accent asset and the widget's code fallback
            // must resolve to the same color in every supported appearance.
            let asset = try #require(UIColor(named: "HonbakoAccent", in: .main, compatibleWith: traits))
            let assetChannels = try rgb(asset.resolvedColor(with: traits))
            #expect(abs(assetChannels.red - channels.red) < 0.0001)
            #expect(abs(assetChannels.green - channels.green) < 0.0001)
            #expect(abs(assetChannels.blue - channels.blue) < 0.0001)
        }
    }

    @Test("White action labels retain accessible contrast in both appearances")
    func actionLabelContrast() throws {
        for (style, contrast, _) in variants {
            let traits = UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: style),
                UITraitCollection(accessibilityContrast: contrast)
            ])
            let background = HonbakoPalette.actionUIColor.resolvedColor(with: traits)
            let ratio = try (luminance(.white) + 0.05) / (luminance(background) + 0.05)
            #expect(ratio >= 4.5, "White text must remain readable on the dune Continue and Resume buttons")
            if contrast == .high { #expect(ratio >= 7) }
        }
    }

    @Test("Dune links retain contrast on light and dark paper, with cached texture tiles")
    func paperContrastAndReuse() throws {
        for (style, contrast, _) in variants {
            let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: style),
                                                       UITraitCollection(accessibilityContrast: contrast)])
            let accent = try luminance(HonbakoPalette.accentUIColor.resolvedColor(with: traits))
            for surface in [HonbakoPaperStock.Surface.page, .card] {
                let background = try luminance(HonbakoPaperStock.base(dark: style == .dark, surface: surface))
                let ratio = (max(accent, background) + 0.05) / (min(accent, background) + 0.05)
                #expect(ratio >= 4.5)
                #expect(HonbakoPaperStock.tile(dark: style == .dark, surface: surface)
                        === HonbakoPaperStock.tile(dark: style == .dark, surface: surface))
            }
        }
    }

    private var variants: [(UIUserInterfaceStyle, UIAccessibilityContrast, UInt32)] {
        [(.light, .normal, 0x806344), (.dark, .normal, 0xCBAA80),
         (.light, .high, 0x674B2F), (.dark, .high, 0xE6CDA8)]
    }

    private func rgb(_ color: UIColor) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        try #require(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        #expect(alpha == 1)
        return (red, green, blue)
    }

    private func luminance(_ color: UIColor) throws -> CGFloat {
        let channels = try rgb(color)
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(channels.red) + 0.7152 * linear(channels.green) + 0.0722 * linear(channels.blue)
    }
}
