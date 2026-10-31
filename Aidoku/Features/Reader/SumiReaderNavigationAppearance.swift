#if SUMI
import UIKit

/// A solid native bar protects titles from both bright and dark page artwork.
@MainActor
enum SumiReaderNavigationAppearance {
    static func configure(_ appearance: UINavigationBarAppearance) {
        appearance.configureWithOpaqueBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = .systemBackground
        appearance.shadowColor = .clear
        appearance.titleTextAttributes[.foregroundColor] = UIColor.label
        appearance.largeTitleTextAttributes[.foregroundColor] = UIColor.label
        if #available(iOS 26.0, *) {
            appearance.subtitleTextAttributes[.foregroundColor] = UIColor.secondaryLabel
        }
    }

    static func apply(to item: UINavigationItem) {
        let appearance = UINavigationBarAppearance()
        configure(appearance)
        item.standardAppearance = appearance
        item.compactAppearance = appearance
        item.scrollEdgeAppearance = appearance
        item.compactScrollEdgeAppearance = appearance
    }

    static func clear(from item: UINavigationItem) {
        item.standardAppearance = nil
        item.compactAppearance = nil
        item.scrollEdgeAppearance = nil
        item.compactScrollEdgeAppearance = nil
    }
}
#endif
