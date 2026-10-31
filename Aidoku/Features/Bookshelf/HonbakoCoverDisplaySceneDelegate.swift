#if SUMI
import SwiftUI
import UIKit

final class HonbakoCoverDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var model: HonbakoCoverDisplayModel?
    private var lastSize: CGSize?
    private var lastOrientation: UIInterfaceOrientation?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard #available(iOS 27.0, *), let scene = scene as? UIWindowScene,
              let model = options.sceneAccessoryUserInfo as? HonbakoCoverDisplayModel else { return }
        self.model = model
        let window = UIWindow(windowScene: scene)
        window.rootViewController = HonbakoCoverDisplayHostingController(rootView: HonbakoCoverDisplayView(model: model))
        window.isUserInteractionEnabled = false
        // This accessory is decorative. It never takes key-window status from
        // the reader, so keyboard input and app navigation stay on the book.
        updateGeometry(of: scene)
        window.isHidden = false
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        model?.setSceneConnected(false, role: scene.session.role.rawValue)
        window = nil
        model = nil
        lastSize = nil
        lastOrientation = nil
    }

    func windowScene(_ windowScene: UIWindowScene, didUpdateEffectiveGeometry previousEffectiveGeometry: UIWindowScene.Geometry) {
        updateGeometry(of: windowScene)
    }

    private func updateGeometry(of scene: UIWindowScene) {
        let geometry = scene.effectiveGeometry
        let size = geometry.coordinateSpace.bounds.size
        // Orientation is used for a physical rotation transform, not to infer
        // available layout space; left and right need opposite corrections.
        let orientation = geometry.interfaceOrientation
        guard size != lastSize || orientation != lastOrientation else { return }
        lastSize = size
        lastOrientation = orientation
        model?.setScenePose(orientation: orientation)
        model?.setSceneConnected(true, role: scene.session.role.rawValue, size: size)
    }
}

#endif
