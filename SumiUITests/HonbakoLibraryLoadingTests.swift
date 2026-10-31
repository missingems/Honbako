import XCTest

final class HonbakoLibraryLoadingTests: XCTestCase {
    @MainActor
    func testHeldStartupShowsCoverSkeletonWithoutEmptyStateOrSpinner() throws {
        let app = launch("--sumi-library-loading-check")
        defer { app.terminate() }
        let loading = element("Honbako.Library.Loading", in: app)
        XCTAssertTrue(loading.waitForExistence(timeout: 15))
        XCTAssertFalse(element("Honbako.Library.Empty", in: app).exists)
        XCTAssertFalse(element("Honbako.Library.LoadError", in: app).exists)
        XCTAssertEqual(app.activityIndicators.count, 0)
        XCTAssertFalse(app.buttons["Find Books"].exists)
        XCTAssertTrue(app.buttons["Honbako.Library.Search"].exists)
        attach(app, "Startup shimmering cover grid")
    }

    @MainActor
    func testVerifiedEmptyLibraryIsCenteredInContentAboveControls() throws {
        let app = launch("--sumi-library-empty-check")
        defer { app.terminate() }
        let empty = element("Honbako.Library.Empty", in: app)
        XCTAssertTrue(empty.waitForExistence(timeout: 15))
        XCTAssertFalse(element("Honbako.Library.Loading", in: app).exists)
        let grid = element("Sumi.Grid", in: app)
        XCTAssertEqual(empty.frame.midY, grid.frame.midY - 16, accuracy: 12,
            "Empty content centers in the available library viewport, above its bottom scroll margin")
        XCTAssertLessThan(empty.frame.maxY, app.buttons["Honbako.Library.Settings"].frame.maxY)
        attach(app, "Verified empty library centered above controls")
    }

    @MainActor
    func testDelayedExistingLibraryNeverExposesAnEmptyState() throws {
        let app = launch("--sumi-library-delayed-check")
        defer { app.terminate() }
        let loading = element("Honbako.Library.Loading", in: app)
        XCTAssertTrue(loading.waitForExistence(timeout: 15))
        let empty = element("Honbako.Library.Empty", in: app)
        let book = app.buttons.matching(identifier: "Sumi.Grid.Book.honbako.tutorial:first-chapter").firstMatch
        let deadline = Date().addingTimeInterval(15)
        while !book.exists, Date() < deadline {
            XCTAssertFalse(empty.exists, "Saved books must never be preceded by a find-books/empty flash")
        }
        XCTAssertTrue(book.exists)
        XCTAssertEqual(book.label, "Existing Library Book")
        XCTAssertFalse(loading.exists)
        XCTAssertFalse(empty.exists)
        attach(app, "Existing books replace loading cards")
    }

    @MainActor
    func testFailedInitialLookupOffersRetryWithoutEmptyLibraryPrompt() throws {
        let app = launch("--sumi-library-error-check")
        defer { app.terminate() }
        XCTAssertTrue(element("Honbako.Library.LoadError", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Try Again"].exists)
        XCTAssertFalse(element("Honbako.Library.Empty", in: app).exists)
        XCTAssertFalse(element("Honbako.Library.Loading", in: app).exists)
        attach(app, "Failed library lookup keeps a retry state")
    }

    @MainActor
    private func launch(_ fixture: String) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = [fixture, "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
