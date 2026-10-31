import XCTest

final class SumiFingerPaperLiveRenderTests: XCTestCase {
    @MainActor
    func testHeldPaperRendersInTheActualAppWindow() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-curl-check"]
        app.launch()
        defer { app.terminate() }
        guard app.navigationBars["Pages 1–2"].waitForExistence(timeout: 12) else {
            throw XCTSkip("This check requires the open landscape book display")
        }
        app.buttons["Hold"].tap()
        // This signal comes from an actual completed GPU command. The app uses
        // its normal event-driven invalidation; the test never forces a draw.
        XCTAssertTrue(app.buttons["Paper ready"].waitForExistence(timeout: 5))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Live finger-held GPU paper"
        capture.lifetime = .keepAlways
        add(capture)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Pages 1–2"].waitForExistence(timeout: 5))
    }
}
