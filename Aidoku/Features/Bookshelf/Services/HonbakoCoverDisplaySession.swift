#if SUMI
import AidokuRunner
import AVFoundation
import UIKit

/// The owner explicitly allows the camera route on hinged hardware. Other
/// installations offer ordinary external-display content without camera access.
@MainActor
final class HonbakoCoverDisplaySession {
    private let model = HonbakoCoverDisplayModel()
    private let camera = HonbakoCoverCamera()
    private weak var owner: UIViewController?
    private var registration: AnyObject?
    private var interaction: (any UIInteraction)?
    private var observers: [NSObjectProtocol] = []
    private var cameraTask: Task<Void, Never>?
    private var generation = UUID()
    private var hingePresent = false
    private var hingeOpen = false
    private var usesCameraAccessory = false
    private var foreground = false
    private var lastShouldRun: Bool?

    func start(on owner: UIViewController, manga: AidokuRunner.Manga, source: AidokuRunner.Source?) {
        guard #available(iOS 27.0, *) else { model.recordUnsupportedSystem(); return }
        model.prepare(manga: manga, source: source)
        self.owner = owner
        foreground = UIApplication.shared.applicationState == .active
        if observers.isEmpty { observeLifecycle() }
        if #available(iOS 27.1, *), HonbakoProStore.personalFeaturesEnabled, interaction == nil {
            let hinge = UIHingeInteraction { [weak self] _, update in
                guard let self else { return }
                hingePresent = update.hinge != nil
                hingeOpen = update.hinge.map { $0.status != .closed && $0.status != .unknown } ?? false
                model.setHinge(present: hingePresent, open: hingeOpen)
                reconcile()
            }
            interaction = hinge
            owner.view.addInteraction(hinge)
        }
        reconcile()
        owner.setNeedsUpdateProperties()
    }

    private var policy: HonbakoCoverCameraPolicy {
        .init(personalBuild: HonbakoProStore.personalFeaturesEnabled, hingePresent: hingePresent,
            hingeOpen: hingeOpen, readerPresented: owner?.presentingViewController != nil,
            coverEnabled: HonbakoCoverDisplayPreferences.showCover(), foreground: foreground)
    }

    private func reconcile() {
        guard #available(iOS 27.0, *), let owner else { return }
        let policy = policy
        let kindChanged = registration == nil || usesCameraAccessory != policy.usesCameraAccessory
        if kindChanged {
            if let registration = registration as? UISceneAccessoryRegistration {
                owner.unregisterSceneAccessory(registration)
            }
            usesCameraAccessory = policy.usesCameraAccessory
            let configuration = UISceneConfiguration()
            configuration.delegateClass = HonbakoCoverDisplaySceneDelegate.self
            let accessory: UISceneAccessory
            if #available(iOS 27.1, *), usesCameraAccessory {
                accessory = .cameraCapture(sceneConfiguration: configuration, userInfo: model)
            } else {
                accessory = .externalNonInteractive(sceneConfiguration: configuration, userInfo: model)
            }
            registration = owner.registerSceneAccessory(accessory)
            model.setAccessoryKind(usesCameraAccessory ? "cameraCapture" : "externalNonInteractive")
        }
        let enabled = policy.coverEnabled && policy.foreground && (!usesCameraAccessory || policy.hingeOpen)
        (registration as? UISceneAccessoryRegistration)?.isEnabled = enabled
        if kindChanged { model.setRegistration(true, enabled: enabled) }
        updateAvailability()
        if lastShouldRun != policy.shouldRunCamera || kindChanged {
            lastShouldRun = policy.shouldRunCamera
            reconcileCamera(running: policy.shouldRunCamera)
        }
    }

    /// UIKit tracks reads of isAvailable during updateProperties.
    func updateAvailability() {
        guard #available(iOS 27.0, *), let registration = registration as? UISceneAccessoryRegistration else { return }
        model.setAvailability(registration.isAvailable, enabled: registration.isEnabled)
    }

    private func reconcileCamera(running: Bool) {
        cameraTask?.cancel()
        generation = UUID()
        let currentGeneration = generation
        let camera = camera
        let model = model
        cameraTask = Task { [weak self] in
            if running {
                let permission = AVCaptureDevice.authorizationStatus(for: .video)
                if permission == .notDetermined {
                    model.setCameraState("requestingPermission")
                    _ = await AVCaptureDevice.requestAccess(for: .video)
                }
                guard !Task.isCancelled, let self, generation == currentGeneration, policy.shouldRunCamera else { return }
                guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                    model.setCameraState("permissionDenied")
                    return
                }
                model.setCameraState("starting")
            }
            let state = await camera.setRunning(running)
            guard !Task.isCancelled, let self, generation == currentGeneration else { return }
            model.setCameraState(state)
            owner?.setNeedsUpdateProperties()
            updateAvailability()
        }
    }

    private func observeLifecycle() {
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.reconcile() } })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in
            self?.foreground = false
            self?.reconcile()
        } })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in
            self?.foreground = true
            self?.reconcile()
        } })
    }

    func stop() {
        cameraTask?.cancel()
        cameraTask = nil
        generation = UUID()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        let owner = owner
        self.owner = nil
        if let interaction { owner?.view.removeInteraction(interaction) }
        interaction = nil
        if #available(iOS 27.0, *), let registration = registration as? UISceneAccessoryRegistration {
            owner?.unregisterSceneAccessory(registration)
        }
        registration = nil
        model.setRegistration(false, enabled: false)
        let camera = camera
        let model = model
        Task { model.setCameraState(await camera.setRunning(false)) }
    }

    deinit {
        cameraTask?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
#endif
