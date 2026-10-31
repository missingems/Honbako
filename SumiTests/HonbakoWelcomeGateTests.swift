@testable import Sumi
import Foundation
import Testing

struct HonbakoWelcomeGateTests {
    @Test("Normal installs see the welcome once, including existing installs without the new completion key")
    func firstPresentation() {
        #expect(HonbakoWelcomeGate.shouldPresent(completedVersion: 0, hasPreviewBooks: false, arguments: [], environment: [:]))
        #expect(HonbakoWelcomeGate.currentVersion == 2)
        #expect(!HonbakoWelcomeGate.shouldPresent(completedVersion: 1, hasPreviewBooks: false, arguments: [], environment: [:]))
        #expect(!HonbakoWelcomeGate.shouldPresent(completedVersion: HonbakoWelcomeGate.currentVersion,
            hasPreviewBooks: false, arguments: [], environment: [:]))
        #expect(!HonbakoWelcomeGate.shouldPresent(completedVersion: HonbakoWelcomeGate.currentVersion + 1,
            hasPreviewBooks: false, arguments: [], environment: [:]))
    }

    @Test("A fresh installation shows the intro after its local completion record is removed")
    func reinstallRestartsWelcome() {
        #expect(!HonbakoWelcomeGate.shouldPresent(completedVersion: 2, hasPreviewBooks: false,
            arguments: [], environment: [:]))
        #expect(HonbakoWelcomeGate.shouldPresent(completedVersion: 0, hasPreviewBooks: false,
            arguments: [], environment: [:]))
    }

    @Test("Unrelated fixtures and test hosts never acquire a blocking welcome presentation")
    func fixtureSuppression() {
        for arguments in [["--sumi-grid-check"], ["--sumi-library-empty-check"], ["--honbako-catalog-check"], ["--honbako-automation-check"]] {
            #expect(!HonbakoWelcomeGate.shouldPresent(completedVersion: 0, hasPreviewBooks: false,
                arguments: arguments, environment: [:]))
        }
        #expect(!HonbakoWelcomeGate.shouldPresent(completedVersion: 0, hasPreviewBooks: true, arguments: [], environment: [:]))
        #expect(!HonbakoWelcomeGate.shouldPresent(completedVersion: 0, hasPreviewBooks: false,
            arguments: [], environment: ["XCTestConfigurationFilePath": "/fixture.xctestconfiguration"]))
    }

    @Test("Explicit onboarding preview works with an already-completed fixture without persisting completion")
    func isolatedPreview() {
        let arguments = ["--sumi-grid-check", HonbakoWelcomeGate.previewArgument]
        #expect(HonbakoWelcomeGate.shouldPresent(completedVersion: HonbakoWelcomeGate.currentVersion,
            hasPreviewBooks: true, arguments: arguments, environment: ["XCTestConfigurationFilePath": "/fixture"]))
        #expect(HonbakoWelcomeGate.completionVersion(from: 0, arguments: arguments) == 0)
        #expect(HonbakoWelcomeGate.completionVersion(from: 0, arguments: []) == HonbakoWelcomeGate.currentVersion)
        #expect(HonbakoWelcomeGate.completionVersion(from: 7, arguments: []) == 7)
    }
}
