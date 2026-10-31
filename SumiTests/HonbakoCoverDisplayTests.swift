@testable import Sumi
import Foundation
import Testing
import UIKit

struct HonbakoCoverDisplayTests {
    @Test("Paid public and personal builds use the optional camera accessory only on hinged hardware")
    func cameraIsHingeOnlyInEveryBuild() {
        for personal in [false, true] {
            for hinge in [false, true] {
                let policy = HonbakoCoverCameraPolicy(personalBuild: personal, verifiedPro: true, hingePresent: hinge,
                    hingeOpen: true, readerPresented: true, coverEnabled: true, foreground: true)
                #expect(policy.usesCameraAccessory == hinge)
                #expect(policy.shouldRunCamera == hinge)
            }
        }
    }

    @Test("Hidden covers, closed folds, dismissed readers and backgrounding all stop the camera")
    func cameraStopsOutsideReading() {
        for personal in [false, true] {
            for closedGate in 0..<4 {
                let policy = HonbakoCoverCameraPolicy(personalBuild: personal, hingePresent: true,
                    hingeOpen: closedGate != 0, readerPresented: closedGate != 1,
                    coverEnabled: closedGate != 2, foreground: closedGate != 3)
                #expect(!policy.shouldRunCamera)
            }
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

    @Test("Cover rotation preserves a portrait print without magnifying it to a landscape viewport")
    func counterRotatedPortraitPrint() {
        let portrait = CGSize(width: 390, height: 844)
        for orientation in [UIInterfaceOrientation.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight] {
            let pose = HonbakoCoverDisplayPose(orientation: orientation)
            let viewport = pose.swapsAxes ? CGSize(width: portrait.height, height: portrait.width) : portrait
            #expect(pose.printSize(in: viewport) == portrait,
                "The unrotated artwork always receives the same portrait-sized canvas, not a zoomed landscape crop")
            let print = CGRect(origin: .zero, size: pose.printSize(in: viewport))
            let rotated = print.applying(CGAffineTransform(rotationAngle: pose.rotation))
            #expect(abs(rotated.width - viewport.width) < 0.001)
            #expect(abs(rotated.height - viewport.height) < 0.001)
        }
        let left = HonbakoCoverDisplayPose(orientation: .landscapeLeft)
        let right = HonbakoCoverDisplayPose(orientation: .landscapeRight)
        #expect(left.rotation == -right.rotation, "Left and right rotations need opposite corrections")
    }

    @MainActor
    @Test("Repeated scene rotations restore the cover pose without clearing its image or connection")
    func rotationDoesNotReconnectAccessory() {
        let model = HonbakoCoverDisplayModel(writesDiagnostics: false)
        model.setSceneConnected(true, role: "externalNonInteractive", size: CGSize(width: 390, height: 844))
        for orientation in [UIInterfaceOrientation.landscapeLeft, .portraitUpsideDown, .landscapeRight, .portrait] {
            model.setScenePose(orientation: orientation)
            #expect(model.status.sceneConnected)
        }
        #expect(model.pose == HonbakoCoverDisplayPose(orientation: .portrait))
        #expect(model.status.imageState == "notRequested", "Rotation never reloads the artwork")
    }


    @Test("An enabled cover preference cannot start a public camera or accessory without verified Pro")
    func coverRequiresCurrentProAccess() {
        let free = HonbakoCoverCameraPolicy(personalBuild: false, verifiedPro: false,
            hingePresent: true, hingeOpen: true, readerPresented: true, coverEnabled: true, foreground: true)
        #expect(!free.hasAccess && !free.shouldEnableAccessory && !free.shouldRunCamera)
        let paid = HonbakoCoverCameraPolicy(personalBuild: false, verifiedPro: true,
            hingePresent: true, hingeOpen: true, readerPresented: true, coverEnabled: true, foreground: true)
        #expect(paid.hasAccess && paid.shouldEnableAccessory && paid.shouldRunCamera)
        let revoked = HonbakoCoverCameraPolicy(personalBuild: false, verifiedPro: false,
            hingePresent: true, hingeOpen: true, readerPresented: true, coverEnabled: true, foreground: true)
        #expect(!revoked.shouldRunCamera && !revoked.shouldEnableAccessory,
            "A revoked subscription stops both outputs even when the saved toggle is still on")
    }

    @Test("Personal cover access stays opt-in and a fresh installation starts with it off")
    func coverStartsOff() throws {
        let suite = "Honbako.CoverPreferences.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!HonbakoCoverDisplayPreferences.showCover(in: defaults))
        defaults.set(true, forKey: HonbakoCoverDisplayPreferences.showCoverKey)
        #expect(HonbakoCoverDisplayPreferences.showCover(in: defaults))
        let personalOff = HonbakoCoverCameraPolicy(personalBuild: true, verifiedPro: false,
            hingePresent: true, hingeOpen: true, readerPresented: true, coverEnabled: false, foreground: true)
        #expect(personalOff.hasAccess && !personalOff.shouldRunCamera && !personalOff.shouldEnableAccessory)
    }

    @Test("Manga cover overrides inherit, isolate by source, and restore the library default")
    func mangaCoverOverrides() throws {
        let suite = "Honbako.CoverOverrides.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = MangaIdentifier(sourceKey: "personal/server", mangaKey: "book.one")
        let sameKeyOtherServer = MangaIdentifier(sourceKey: "personal", mangaKey: "server/book.one")
        #expect(HonbakoCoverDisplayPreferences.mangaMode(for: first, in: defaults) == .libraryDefault)
        #expect(!HonbakoCoverDisplayPreferences.showCover(for: first, in: defaults))
        defaults.set(true, forKey: HonbakoCoverDisplayPreferences.showCoverKey)
        #expect(HonbakoCoverDisplayPreferences.showCover(for: first, in: defaults))
        HonbakoCoverDisplayPreferences.setMangaMode(.disabled, for: first, in: defaults)
        #expect(!HonbakoCoverDisplayPreferences.showCover(for: first, in: defaults))
        #expect(HonbakoCoverDisplayPreferences.showCover(for: sameKeyOtherServer, in: defaults))
        HonbakoCoverDisplayPreferences.setMangaMode(.enabled, for: first, in: defaults)
        defaults.set(false, forKey: HonbakoCoverDisplayPreferences.showCoverKey)
        #expect(HonbakoCoverDisplayPreferences.showCover(for: first, in: defaults))
        #expect(!HonbakoCoverDisplayPreferences.showCover(for: sameKeyOtherServer, in: defaults))
        HonbakoCoverDisplayPreferences.setMangaMode(.libraryDefault, for: first, in: defaults)
        #expect(!HonbakoCoverDisplayPreferences.showCover(for: first, in: defaults))
        #expect(!HonbakoCoverDisplayPreferences.showCover(in: defaults), "Overrides never rewrite the library default")
    }

}
