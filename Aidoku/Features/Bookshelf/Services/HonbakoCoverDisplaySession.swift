#if SUMI
import AidokuRunner
import UIKit

/// Registers ordinary non-interactive content without a capture session. An
/// unavailable accessory is harmless and cannot be forced onto the Duo cover.
@MainActor
final class HonbakoCoverDisplaySession {
    private let model = HonbakoCoverDisplayModel()
    private weak var owner: UIViewController?
    // Keep this type-erased so the reader can still run on iOS before 27.
    private var registration: AnyObject?
    private var preferenceObserver: NSObjectProtocol?

    func start(on owner: UIViewController, manga: AidokuRunner.Manga, source: AidokuRunner.Source?) {
        guard #available(iOS 27.0, *) else {
            model.recordUnsupportedSystem()
            return
        }
        model.prepare(manga: manga, source: source)
        if registration == nil {
            self.owner = owner
            // Accessory scenes receive their role from the system, rather than
            // a scene manifest or a role chosen by the app.
            let configuration = UISceneConfiguration()
            configuration.delegateClass = HonbakoCoverDisplaySceneDelegate.self
            let accessory = UISceneAccessory.externalNonInteractive(sceneConfiguration: configuration, userInfo: model)
            let registration = owner.registerSceneAccessory(accessory)
            registration.isEnabled = HonbakoCoverDisplayPreferences.showCover()
            self.registration = registration
            model.setRegistration(true, enabled: registration.isEnabled)
            preferenceObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updatePreference() }
            }
        }
        owner.setNeedsUpdateProperties()
        updateAvailability()
    }

    /// Reading this from UIViewController.updateProperties participates in
    /// UIKit's automatic observation of accessory availability.
    func updateAvailability() {
        guard #available(iOS 27.0, *), let registration = registration as? UISceneAccessoryRegistration else { return }
        model.setAvailability(registration.isAvailable, enabled: registration.isEnabled)
    }

    private func updatePreference() {
        guard #available(iOS 27.0, *), let registration = registration as? UISceneAccessoryRegistration else { return }
        registration.isEnabled = HonbakoCoverDisplayPreferences.showCover()
        updateAvailability()
        owner?.setNeedsUpdateProperties()
    }

    func stop() {
        if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
        preferenceObserver = nil
        if #available(iOS 27.0, *), let registration = registration as? UISceneAccessoryRegistration {
            owner?.unregisterSceneAccessory(registration)
        }
        registration = nil
        owner = nil
        model.setRegistration(false, enabled: false)
    }

    deinit {
        if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
    }
}
#endif
