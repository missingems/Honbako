#if SUMI
import SwiftUI
import UIKit

final class HonbakoCoverDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var model: HonbakoCoverDisplayModel?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard #available(iOS 27.0, *), let scene = scene as? UIWindowScene,
              let model = options.sceneAccessoryUserInfo as? HonbakoCoverDisplayModel else { return }
        self.model = model
        let window = UIWindow(windowScene: scene)
        window.rootViewController = HonbakoCoverDisplayHostingController(rootView: HonbakoCoverDisplayView(model: model))
        window.isUserInteractionEnabled = false
        // This accessory is decorative. It never takes key-window status from
        // the reader, so keyboard input and app navigation stay on the book.
        window.isHidden = false
        self.window = window
        model.setSceneConnected(true, role: session.role.rawValue, size: scene.coordinateSpace.bounds.size)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        model?.setSceneConnected(false, role: scene.session.role.rawValue)
        window = nil
        model = nil
    }

    func windowScene(_ windowScene: UIWindowScene, didUpdate previousCoordinateSpace: UICoordinateSpace,
                     interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
                     traitCollection previousTraitCollection: UITraitCollection) {
        model?.setSceneConnected(true, role: windowScene.session.role.rawValue,
            size: windowScene.coordinateSpace.bounds.size)
    }
}

#endif
