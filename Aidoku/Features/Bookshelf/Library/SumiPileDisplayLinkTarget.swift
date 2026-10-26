#if SUMI
import QuartzCore

/// CADisplayLink retains its target. Keeping the view weak avoids an offscreen
/// scene being held alive if its enclosing presentation is torn down abruptly.
final class SumiPileDisplayLinkTarget: NSObject {
    weak var view: SumiBookPileView?
    init(view: SumiBookPileView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) { view?.simulationTick(link) }
}
#endif
