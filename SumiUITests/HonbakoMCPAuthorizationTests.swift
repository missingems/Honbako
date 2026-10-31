import XCTest

final class HonbakoMCPAuthorizationTests: XCTestCase {
    @MainActor
    func testAIApprovalLinkResumesBackgroundedAppAndOffersAccurateRecovery() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        // This fixture never loads real pairing credentials or contacts a server.
        app.launchArguments = ["--sumi-library-empty-check", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Honbako.Library.Settings"].waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        let id = UUID().uuidString.lowercased()
        app.open(try XCTUnwrap(URL(string: "honbako://mcp-authorize?request=\(id)")))
        XCTAssertTrue(app.navigationBars["Connect Your AI"].waitForExistence(timeout: 10))
        let explanation = app.staticTexts["Enable your remote MCP server in Settings, then try this request again. If it is already enabled, reconnect it first."]
        XCTAssertTrue(explanation.waitForExistence(timeout: 10))
        let retry = app.buttons["Honbako.MCP.Authorization.Retry"]
        XCTAssertTrue(retry.isHittable)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "expired")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Allow Connection"].exists, "An unverified request must never offer approval")
        retry.tap()
        XCTAssertTrue(explanation.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Allow Connection"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "AI connection recovery after returning to Honbako"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Honbako.Library.Settings"].waitForExistence(timeout: 5))
    }
}
