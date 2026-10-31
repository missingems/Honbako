import UIKit
import XCTest

final class SumiReaderControlsVisibilityTests: XCTestCase {
    @MainActor
    func testPortraitControlsStayUntilTapOrPageTurn() throws {
        try checkControls(orientation: .portrait)
    }

    @MainActor
    func testLandscapeControlsStayUntilTapOrPageTurn() throws {
        try checkControls(orientation: .landscapeLeft)
    }

    @MainActor
    private func checkControls(orientation: UIDeviceOrientation) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check", "--sumi-grid-reading-mode=ltr",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let book = app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-001"]
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(wait {
            !window.frame.isEmpty && (window.frame.width > window.frame.height) == orientation.isLandscape
        }, "The reader check must run in its requested display orientation")
        book.tap()
        let close = app.buttons["SumiReader.Close"]
        XCTAssertTrue(wait { close.exists && close.isHittable })
        assertStaysVisible(close)
        let reader = item("Sumi.DirectReader", app)
        let page = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@",
            ["sumi.reader.slide", "sumi.reader.curl"])).firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        let openingPosition = reader.value as? String

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(wait { close.exists && close.isHittable })
        assertStaysVisible(close)
        XCTAssertEqual(reader.value as? String, openingPosition)

        page.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.4)).tap()
        XCTAssertTrue(wait { !close.isHittable })
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertFalse(close.isHittable, "Returning to the foreground must preserve an explicit hide")
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.4)).tap()
        XCTAssertTrue(wait { close.isHittable })
        assertStaysVisible(close)

        let beforeTurn = reader.value as? String
        page.swipeLeft()
        XCTAssertTrue(wait { !close.isHittable })
        XCTAssertTrue(wait { (reader.value as? String) != beforeTurn })
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.4)).tap()
        XCTAssertTrue(wait { close.isHittable })
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Reader controls stay visible until an explicit interaction"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func assertStaysVisible(_ close: XCUIElement) {
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !close.isHittable }, object: close)
        hidden.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed,
            "The toolbar must stay visible without a swipe or tap")
    }

    @MainActor
    private func item(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    private func wait(_ predicate: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)], timeout: 12) == .completed
    }
}
