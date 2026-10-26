#if SUMI
import Foundation
import SceneKit

/// SceneKit invokes this on its render thread. Only first-frame acknowledgments
/// cross to UIKit; no UI or persistence runs on the renderer's queue.
final class SumiPileRendererObserver: NSObject, SCNSceneRendererDelegate {
    weak var view: SumiBookPileView?
    private let lock = NSLock()
    private var pendingGeneration: Int?
    private var inFlightGeneration: Int?

    func requestFrame(generation: Int) {
        lock.lock()
        pendingGeneration = generation
        lock.unlock()
    }

    func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
        lock.lock()
        inFlightGeneration = pendingGeneration
        pendingGeneration = nil
        lock.unlock()
    }

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        lock.lock()
        let generation = inFlightGeneration
        inFlightGeneration = nil
        lock.unlock()
        guard let generation else { return }
        DispatchQueue.main.async { [weak self] in self?.view?.rendererDidRenderFrame(generation: generation) }
    }
}
#endif
