import UIKit
import XCTest

final class HonbakoAutomaticPageAccessInteractionTests: XCTestCase {
    @MainActor
    func testConnectedAssistantAnnotatesPagedReaderWithoutClosingTheBook() {
        verifyAutomaticAccess(mode: "rtl", orientation: .portrait)
    }

    @MainActor
    func testConnectedAssistantAnnotatesScrollingReaderWithoutClosingTheBook() {
        verifyAutomaticAccess(mode: "webtoon", orientation: .landscapeLeft)
    }

    @MainActor
    private func verifyAutomaticAccess(mode: String, orientation: UIDeviceOrientation) {
        continueAfterFailure = false
        let previous = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check", "--sumi-grid-reading-mode=\(mode)",
                               "--honbako-page-access-check", "-AppleLanguages", "(en)",
                               "-AppleLocale", "en_US", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = previous }
        let book = app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-002"]
        XCTAssertTrue(book.waitForExistence(timeout: 20))
        book.tap()
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 20))
        XCTAssertTrue(wait { (reader.value as? String)?.contains("page 4") == true })
        let mark = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@",
            "Your connected assistant can annotate this page")).firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 15), "Automatic image publication and returned annotation must work without a sharing action")
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertTrue(reader.exists)
        let chapters = app.buttons["Sumi.Reader.ChaptersButton"]
        if !chapters.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)).tap() }
        XCTAssertTrue(chapters.waitForExistence(timeout: 8))
        chapters.tap()
        XCTAssertTrue(item("Sumi.Reader.Chapters", app).waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Honbako.Reader.PageCoaching.Action"].exists)
        XCTAssertFalse(app.buttons["Start Page Coaching"].exists)
        XCTAssertFalse(app.buttons["Stop Page Coaching"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(wait { mark.exists && reader.exists })
        XCTAssertTrue((reader.value as? String)?.contains("page 4") == true)
        XCTAssertEqual(app.alerts.count, 0)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Automatic connected assistant annotation in \(mode)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let close = app.buttons["SumiReader.Close"]
        if !close.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)).tap() }
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        close.tap()
        XCTAssertTrue(wait { !reader.exists })
        XCTAssertTrue(book.waitForExistence(timeout: 10))
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
