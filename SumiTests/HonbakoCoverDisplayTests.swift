@testable import Sumi
import Foundation
import Testing

struct HonbakoCoverDisplayTests {
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
