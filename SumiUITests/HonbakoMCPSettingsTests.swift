import XCTest

final class HonbakoMCPSettingsTests: XCTestCase {
    @MainActor
    func testConnectionModesURLAndPermissionsUseSimpleNativeSettings() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        defer { app.terminate() }
        let settings = app.buttons["Honbako.Library.Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let mcp = app.descendants(matching: .any).matching(identifier: "Honbako.Automation").firstMatch
        for _ in 0..<6 {
            if mcp.exists && mcp.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(mcp.isHittable)
        mcp.tap()
        XCTAssertTrue(app.navigationBars["MCP Server"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["Remote"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["Local"].exists)
        XCTAssertTrue(app.switches["Honbako.MCP.Enable"].exists)
        XCTAssertTrue(app.staticTexts["Honbako.MCP.URL"].exists)
        XCTAssertFalse(app.staticTexts["1. Enable Your Server"].exists)
        XCTAssertFalse(app.staticTexts["Last Update"].exists)
        XCTAssertFalse(app.staticTexts["Honbako.MCP.BetaPurchases"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "Honbako.Automation.Status").firstMatch.exists)
        attach(app, "Remote connection and visible MCP URL")
        app.segmentedControls.buttons["Local"].tap()
        XCTAssertTrue(app.textFields["Honbako.Automation.Endpoint"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["Honbako.Automation.Code"].exists)
        XCTAssertFalse(app.buttons["Honbako.Automation.Connect"].isEnabled)
        app.segmentedControls.buttons["Remote"].tap()
        for key in ["LibraryAccess", "History", "PageAccess", "LibraryChanges", "SourceChanges", "Annotations"] {
            let toggle = app.switches["Honbako.MCP.Permission.\(key)"]
            for _ in 0..<6 {
                if toggle.exists && toggle.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(toggle.exists, "Missing permission: \(key)")
        }
        attach(app, "MCP access and write permissions")
    }
    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
