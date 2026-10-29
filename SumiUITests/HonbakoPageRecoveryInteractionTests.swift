import UIKit
import XCTest

final class HonbakoPageRecoveryInteractionTests: XCTestCase {
    @MainActor
    func testSavedFailedPageOpensAndRetriesWithoutMixedLoadingState() {
        verifyFailureRecovery(mode: "rtl", rotates: true)
    }

    @MainActor
    func testScrollingReaderOffersTheSameRecoverablePageState() {
        verifyFailureRecovery(mode: "webtoon", rotates: false, startingOrientation: .landscapeLeft)
    }

    @MainActor
    private func verifyFailureRecovery(mode: String, rotates: Bool, startingOrientation: UIDeviceOrientation = .portrait) {
        continueAfterFailure = false
        let previous = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = startingOrientation
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check", "--sumi-grid-reading-mode=\(mode)",
                               "--honbako-page-failure-check", "-AppleLanguages", "(en)",
                               "-AppleLocale", "en_US", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = previous }
        let book = app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-002"]
        XCTAssertTrue(book.waitForExistence(timeout: 20))
        book.tap()
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 20), "A failed saved page must open its reader, not a source error over the cover")
        XCTAssertTrue(wait { (reader.value as? String)?.contains("page 4") == true })
        let error = item("Sumi.Reader.Page.Error", app)
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(wait { self.retry(app) != nil }, "The page error must have one tappable retry")
        XCTAssertFalse(item("Sumi.Reader.Page.Loading", app).exists, "A finished failure must not retain its loading spinner")
        attach(app, "\(mode) saved page failure is recoverable")
        if rotates {
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(wait {
                guard let retry = self.retry(app) else { return false }
                return app.windows.allElementsBoundByIndex.contains {
                    $0.isHittable && $0.frame.width > $0.frame.height
                        && $0.frame.intersects(reader.frame) && $0.frame.contains(retry.frame)
                }
            }, "Visible windows: \(app.windows.allElementsBoundByIndex.map { $0.frame }); reader: \(reader.frame); retry: \(String(describing: self.retry(app)?.frame))")
            XCTAssertTrue((reader.value as? String)?.contains("page 4") == true)
            attach(app, "Landscape page failure stays readable and tappable")
            // Exercise retry and reopening in the rotated reader layout.
        }
        retry(app)?.tap()
        XCTAssertTrue(wait { !error.exists }, "Retry must replace the error with the recovered artwork")
        XCTAssertFalse(item("Sumi.Reader.Page.Loading", app).exists)
        XCTAssertTrue((reader.value as? String)?.contains("page 4") == true, "Retry must retain the saved canonical page")
        attach(app, "\(mode) retry recovers the same page")
        let close = app.buttons["SumiReader.Close"]
        if !close.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45)).tap() }
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        close.tap()
        XCTAssertTrue(wait { !reader.exists })
        XCTAssertTrue(book.waitForExistence(timeout: 8))
        book.tap()
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        XCTAssertTrue(wait { (reader.value as? String)?.contains("page 4") == true })
        XCTAssertFalse(error.exists, "Reopening the recovered page must not restore its earlier failure")
    }

    @MainActor
    private func retry(_ app: XCUIApplication) -> XCUIElement? {
        app.buttons.matching(identifier: "Sumi.Reader.Page.Retry").allElementsBoundByIndex.first { $0.isHittable }
    }

    @MainActor
    private func item(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    private func wait(_ predicate: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)], timeout: 12) == .completed
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
