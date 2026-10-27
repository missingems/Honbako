#if SUMI
import UIKit

/// Live refraction surrounds only the lifted print. The strip keeps its flat
/// thumbnails, and the page itself stays sharp above this glass surface.
final class SumiScrubHoverGlassView: UIVisualEffectView {
    static let outset: CGFloat = 7
    private static let peakScale: CGFloat = 1.025
    private static let rippleKey = "Sumi.HoverGlass.Ripple"

    init() {
        super.init(effect: nil)
        accessibilityIdentifier = "Sumi.Reader.ScrubPreview.Glass"
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        layer.cornerCurve = .continuous
        clipsToBounds = true
        updateMaterial()
        NotificationCenter.default.addObserver(self, selector: #selector(updateMaterial),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func fit(around printBounds: CGRect) {
        guard printBounds.width > 1, printBounds.height > 1 else {
            isHidden = true
            frame = .zero
            stopRipple()
            return
        }
        isHidden = false
        // One concentric glass lip follows either a single page or a spread.
        // It is a child of the hover, so lift, motion and dismissal stay joined.
        frame = printBounds.insetBy(dx: -Self.outset, dy: -Self.outset)
        layer.cornerRadius = SumiPreviewGeometry.radius(in: printBounds) + Self.outset
    }

    func ripple() {
        layer.removeAnimation(forKey: Self.rippleKey)
        guard !isHidden, window != nil, !UIAccessibility.isReduceMotionEnabled,
              !UIAccessibility.isReduceTransparencyEnabled else { return }
        // Animate only the refracting surface. Text and artwork never wobble.
        let wave = CAKeyframeAnimation(keyPath: "transform.scale")
        wave.values = [1, Self.peakScale, 0.995, 1]
        wave.keyTimes = [0, 0.32, 0.68, 1]
        wave.timingFunctions = [CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        wave.duration = 0.48
        layer.add(wave, forKey: Self.rippleKey)
    }

    func stopRipple() {
        layer.removeAnimation(forKey: Self.rippleKey)
    }

    static func maximumOutset(for printSize: CGSize) -> CGFloat {
        // Reserve the lip's peak spring extent as well as its resting width.
        outset + ceil((max(printSize.width, printSize.height) + outset * 2) * (peakScale - 1) / 2)
    }

    @objc private func updateMaterial() {
        if UIAccessibility.isReduceTransparencyEnabled {
            effect = nil
            contentView.backgroundColor = .secondarySystemBackground
        } else {
            contentView.backgroundColor = .clear
            let glass = UIGlassEffect(style: .clear)
            glass.isInteractive = false
            effect = glass
        }
    }
}
#endif
