#if SUMI
import UIKit

/// Anchor the discrete paper contacts to the actual reader, including its
/// display and touch position. Core Haptics supplies the moving-paper texture.
@MainActor
final class SumiPaperTouchFeedback {
    private weak var view: UIView?
    private var lift: UIImpactFeedbackGenerator?
    private var release: UIImpactFeedbackGenerator?
    private var location: CGPoint?

    var isAttached: Bool { view?.window != nil }

    func prepare(in view: UIView?) {
        if let view, self.view !== view {
            self.view = view
            lift = UIImpactFeedbackGenerator(style: .light, view: view)
            release = UIImpactFeedbackGenerator(style: .medium, view: view)
        }
        lift?.prepare()
        release?.prepare()
    }

    func update(location: CGPoint?) {
        if let location, location.x.isFinite, location.y.isFinite { self.location = location }
    }

    @discardableResult
    func play(releasing: Bool, intensity: Float) -> Bool {
        guard let view, view.window != nil else { return false }
        let generator = releasing ? release : lift
        guard let generator else { return false }
        let point = location ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        generator.impactOccurred(intensity: CGFloat(intensity), at: point)
        return true
    }
}
#endif
