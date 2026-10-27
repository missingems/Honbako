@testable import Sumi
import Foundation
import Testing

struct HonbakoCoverDisplayTests {
    @Test("Camera permission is never needed for ordinary hardware or nonpersonal builds")
    func cameraIsOwnerAndHingeOnly() {
        for personal in [false, true] {
            for hinge in [false, true] {
                let policy = HonbakoCoverCameraPolicy(personalBuild: personal, hingePresent: hinge,
                    hingeOpen: true, readerPresented: true, coverEnabled: true, foreground: true)
                #expect(policy.shouldRunCamera == (personal && hinge))
            }
        }
    }

    @Test("Hidden covers, closed folds, dismissed readers and backgrounding all stop the camera")
    func cameraStopsOutsideReading() {
        for closedGate in 0..<4 {
            let policy = HonbakoCoverCameraPolicy(personalBuild: true, hingePresent: true,
                hingeOpen: closedGate != 0, readerPresented: closedGate != 1,
                coverEnabled: closedGate != 2, foreground: closedGate != 3)
            #expect(!policy.shouldRunCamera)
        }
    }

    @MainActor
    @Test("Closing a reader withdraws its accessory and clears stale availability")
    func closingWithdrawsCover() {
        let model = HonbakoCoverDisplayModel(writesDiagnostics: false)
        model.setRegistration(true, enabled: true)
        model.setAvailability(true, enabled: true)
        model.setSceneConnected(true, role: "externalNonInteractive")
        #expect(model.status.sceneConnected && model.status.available && model.status.enabled)

        model.setRegistration(false, enabled: false)
        #expect(!model.status.registered && !model.status.available)
        #expect(!model.status.enabled && !model.status.sceneConnected)
        #expect(model.status.accessoryKind == "externalNonInteractive")
    }

    @MainActor
    @Test("Hiding the cover preserves system availability instead of pretending the display disconnected")
    func hiddenCoverPreservesAvailability() {
        let model = HonbakoCoverDisplayModel(writesDiagnostics: false)
        model.setRegistration(true, enabled: true)
        model.setAvailability(true, enabled: true)
        model.setAvailability(true, enabled: false)
        #expect(model.status.registered && model.status.available && !model.status.enabled)
        model.setAvailability(false, enabled: false)
        #expect(!model.status.available && !model.status.enabled)
    }
}
