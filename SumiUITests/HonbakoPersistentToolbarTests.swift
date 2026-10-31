import XCTest

final class HonbakoPersistentToolbarTests: XCTestCase {
    @MainActor
    func testBottomControlsSurviveLandscapeScrollingAndRotation() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let grid = app.descendants(matching: .any).matching(identifier: "Sumi.Grid").firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 20))
        let settings = app.buttons["Honbako.Library.Settings"]
        XCTAssertFalse(app.navigationBars["Library"].exists)
        XCTAssertFalse(app.staticTexts["Reading"].exists)
        XCTAssertFalse(app.staticTexts["Finished"].exists)
        assertVisible(app, settings: settings)
        attach(app, "Bottom-right library controls in landscape")
        grid.swipeUp()
        assertVisible(app, settings: settings)
        grid.swipeDown()
        assertVisible(app, settings: settings)
        XCUIDevice.shared.orientation = .portrait
        assertVisible(app, settings: settings)
        XCUIDevice.shared.orientation = .landscapeRight
        assertVisible(app, settings: settings)
        try app.openHonbakoSearch()
        app.honbakoSearchField.typeText("042")
        XCTAssertTrue(app.buttons["Sumi.Search.Book.sumi-grid-preview:book-042"].waitForExistence(timeout: 8))
        XCTAssertFalse(settings.isHittable, "The glass search owns focus while open")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Honbako.Search.Results").firstMatch.exists)
        XCTAssertTrue(app.buttons["Honbako.Library.CloseSearch"].isHittable)
        attach(app, "Landscape glass search with Settings")
        app.closeHonbakoSearch()
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        assertVisible(app, settings: settings)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }

    @MainActor
    func testSettingsShowMCPConnectionGuideAndSideBySidePlans() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        defer { app.terminate() }
        let settings = app.buttons["Honbako.Library.Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Getting Started"].exists)
        let mcp = app.descendants(matching: .any).matching(identifier: "Honbako.Automation").firstMatch
        for _ in 0..<6 {
            if mcp.exists, mcp.isHittable { break }
            try scrollSettings(app)
        }
        XCTAssertTrue(mcp.isHittable)
        mcp.tap()
        XCTAssertTrue(app.navigationBars["MCP Server"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["Honbako.Automation.Endpoint"].exists)
        XCTAssertFalse(app.secureTextFields["Honbako.Automation.Code"].exists)
        let enableMCP = app.switches["Honbako.MCP.Enable"]
        XCTAssertTrue(enableMCP.exists)
        XCTAssertTrue(enableMCP.isEnabled, "An unavailable remote service must not leave a silently disabled switch")
        let remoteStatus = app.staticTexts["Honbako.MCP.RemoteStatus"]
        XCTAssertTrue(remoteStatus.waitForExistence(timeout: 5))
        enableMCP.tap()
        XCTAssertEqual(enableMCP.value as? String, "0", "A failed availability check cannot claim an active server")
        XCTAssertTrue(enableMCP.isEnabled)
        XCTAssertFalse(app.navigationBars["Honbako Pro"].exists, "Do not sell hosting while the service is unavailable")
        let retry = app.buttons["Honbako.MCP.Retry"]
        XCTAssertTrue(retry.isHittable)
        retry.tap()
        XCTAssertTrue(enableMCP.isEnabled)
        XCTAssertTrue(remoteStatus.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Honbako.MCP.Local").firstMatch.exists)
        attach(app, "Remote setup status with usable MCP switch and retry")
        let grok = app.descendants(matching: .any).matching(identifier: "Honbako.MCP.Guide.grok").firstMatch
        for _ in 0..<6 {
            if grok.exists, grok.isHittable { break }
            try scrollSettings(app, title: "MCP Server")
        }
        XCTAssertTrue(grok.isHittable)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Honbako.MCP.Guide.chatgpt").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Honbako.MCP.Guide.claude").firstMatch.exists)
        grok.tap()
        XCTAssertTrue(app.navigationBars["Grok / Grok Bot"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Connection Details"].exists)
        goBack(app, title: "Grok / Grok Bot")
        app.descendants(matching: .any).matching(identifier: "Honbako.MCP.Guide.chatgpt").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["ChatGPT"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["OAuth support needed"].exists)
        XCTAssertTrue(app.staticTexts["Connection Details"].exists)
        goBack(app, title: "ChatGPT")
        app.descendants(matching: .any).matching(identifier: "Honbako.MCP.Guide.claude").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Claude"].waitForExistence(timeout: 5))
        goBack(app, title: "Claude")
        XCTAssertFalse(app.navigationBars["AI Connections"].exists)
        attach(app, "MCP setup from the assistant perspective")
        goBack(app, title: "MCP Server")
        let pro = app.buttons["Honbako Pro"]
        for _ in 0..<6 {
            if pro.exists, pro.isHittable { break }
            try scrollSettings(app)
        }
        XCTAssertTrue(pro.isHittable)
        pro.tap()
        XCTAssertTrue(app.navigationBars["Honbako Pro"].waitForExistence(timeout: 5))
        let free = app.staticTexts["Free"]
        let premium = app.staticTexts["Pro"]
        XCTAssertTrue(free.waitForExistence(timeout: 5))
        XCTAssertTrue(premium.exists)
        XCTAssertLessThan(free.frame.midX, premium.frame.midX)
        XCTAssertEqual(free.frame.minY, premium.frame.minY, accuracy: 2)
        attach(app, "Free and Pro plans side by side")
    }

    @MainActor
    func testFinalCoverScrollsClearOfBottomButtons() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let grid = app.descendants(matching: .any).matching(identifier: "Sumi.Grid").firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        let settings = app.buttons["Honbako.Library.Settings"]
        let last = app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-100"]
        let window = try XCTUnwrap(app.windows.allElementsBoundByIndex.first {
            $0.isHittable && $0.frame.intersects(grid.frame) && $0.frame.width > $0.frame.height
        })
        let viewport = grid.frame.intersection(window.frame)
        let origin = window.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: viewport.midX - window.frame.minX,
            dy: viewport.maxY - window.frame.minY - viewport.height * 0.15))
        let end = origin.withOffset(CGVector(dx: viewport.midX - window.frame.minX,
            dy: viewport.minY - window.frame.minY + viewport.height * 0.15))
        for _ in 0..<18 {
            if last.exists, last.isHittable, last.frame.maxY < settings.frame.minY - 12 { break }
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0.05)
        }
        XCTAssertTrue(last.exists && last.isHittable)
        XCTAssertLessThan(last.frame.maxY, settings.frame.minY - 12)
        XCTAssertTrue(settings.isHittable)
        attach(app, "Final cover scrolls above the floating buttons")
    }

    @MainActor
    private func goBack(_ app: XCUIApplication, title: String) {
        let sideBack = app.descendants(matching: .any).matching(identifier: "BackButton").firstMatch
        let back = sideBack.exists ? sideBack : app.navigationBars[title].buttons.element(boundBy: 0)
        XCTAssertTrue(back.isHittable)
        back.tap()
    }

    @MainActor
    private func scrollSettings(_ app: XCUIApplication, title: String = "Settings") throws {
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.exists)
        let window = try XCTUnwrap(app.windows.allElementsBoundByIndex.first {
            $0.isHittable && $0.frame.contains(bar.frame)
        })
        let viewport = CGRect(x: bar.frame.minX, y: bar.frame.maxY,
            width: bar.frame.width, height: window.frame.maxY - bar.frame.maxY)
        let origin = window.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: viewport.midX - window.frame.minX,
            dy: viewport.maxY - window.frame.minY - viewport.height * 0.2))
        let end = origin.withOffset(CGVector(dx: viewport.midX - window.frame.minX,
            dy: viewport.minY - window.frame.minY + viewport.height * 0.2))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
    }

    @MainActor
    private func assertVisible(_ app: XCUIApplication, settings: XCUIElement) {
        XCTAssertTrue(app.honbakoSearchEntry.waitForExistence(timeout: 5))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.honbakoSearchEntry.isHittable && settings.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, app.debugDescription)
        let window = app.windows.allElementsBoundByIndex.filter {
            $0.isHittable && $0.frame.contains(settings.frame)
        }.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        if let window {
            XCTAssertGreaterThan(settings.frame.midX, window.frame.midX)
            XCTAssertGreaterThan(settings.frame.midY, window.frame.minY + window.frame.height * 0.65)
            XCTAssertEqual(settings.frame.maxX, window.frame.maxX - 16, accuracy: 2,
                "Bottom controls stay at the display edge instead of reserving the vertical sidebar’s empty strip")
            XCTAssertLessThanOrEqual(settings.frame.maxY, window.frame.maxY)
            let grid = app.descendants(matching: .any).matching(identifier: "Sumi.Grid").firstMatch
            XCTAssertEqual(grid.frame.minX, window.frame.minX, accuracy: 1)
            XCTAssertEqual(grid.frame.maxX, window.frame.maxX, accuracy: 1)
        }
        XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
        XCTAssertEqual(settings.frame.width, settings.frame.height, accuracy: 1)
        XCTAssertEqual(app.honbakoSearchEntry.frame.width, app.honbakoSearchEntry.frame.height, accuracy: 1)
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let surface = app.windows.allElementsBoundByIndex.filter { $0.isHittable && !$0.frame.isEmpty }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        let capture = XCTAttachment(screenshot: surface?.screenshot() ?? app.screenshot())
        capture.name = name; capture.lifetime = .keepAlways; add(capture)
    }
}
