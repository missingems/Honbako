@testable import Aidoku
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct ReaderPageTurnCadenceTests {
    @Test("Native turn hints respect the attached display capability and cap the request at 120")
    func displayCapability() {
        for (display, minimum, maximum) in [(60, 60, 60), (80, 80, 80), (120, 80, 120), (144, 80, 120)] {
            let range = ReaderPageTurnCadence.preferredRange(maximumFramesPerSecond: display)
            #expect(range.minimum == Float(minimum))
            #expect(range.maximum == Float(maximum))
            #expect(range.preferred == Float(maximum))
        }
        let unknown = ReaderPageTurnCadence.preferredRange(maximumFramesPerSecond: 0)
        #expect(unknown.minimum == CAFrameRateRange.default.minimum)
        #expect(unknown.maximum == CAFrameRateRange.default.maximum)
    }

    @available(iOS 18.0, *)
    @Test("A prepared passive hint activates only for a visible attached reader and stops after the turn")
    func passiveLifecycle() throws {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let controller = UIViewController()
        controller.loadViewIfNeeded()
        let cadence = ReaderPageTurnCadence(view: controller.view)
        cadence.setActive(true)
        #expect(!cadence.isActive)
        #expect(!cadence.requiresContinuousUpdates)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.isHidden = false
        defer {
            cadence.setActive(false)
            window.isHidden = true
            window.rootViewController = nil
        }
        cadence.setActive(true)
        #expect(cadence.isActive)
        #expect(!cadence.requiresContinuousUpdates)
        let range = try #require(cadence.preferredFrameRateRange)
        #expect(range.maximum == Float(min(120, scene.screen.maximumFramesPerSecond)))
        #expect(range.preferred == range.maximum)
        cadence.setActive(false)
        #expect(!cadence.isActive)
        window.isHidden = true
        cadence.setActive(true)
        #expect(!cadence.isActive)
        #expect(!cadence.requiresContinuousUpdates)
        #endif
    }
}
