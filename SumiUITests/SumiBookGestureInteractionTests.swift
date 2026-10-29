import XCTest
import UIKit

final class SumiBookGestureInteractionTests: XCTestCase {
    @MainActor
    func testPinchCanCancelThenCloseWithoutChangingReadingPosition() throws {
        let app = launch(diagnosePinch: true)
        defer { app.terminate() }
        let grid = item("Sumi.Grid", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-001"].tap()
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["SumiReader.Close"].waitForExistence(timeout: 5))
        let position = try XCTUnwrap(reader.value as? String)
        let portrait = item("sumi.reader.slide", app)
        let pager = portrait.exists ? portrait : item("sumi.reader.curl", app)
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        let close = app.buttons["SumiReader.Close"]
        for _ in 0..<2 {
            if !close.isHittable { break }
            pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        }
        XCTAssertTrue(wait(NSPredicate { _, _ in !close.isHittable }, close),
                      "Hide controls before pinching the actual page; a root-level gesture can hit the toolbar")
        pager.pinch(withScale: 1.15, velocity: 0.3)
        XCTAssertTrue(reader.waitForExistence(timeout: 5))
        XCTAssertEqual(reader.value as? String, position, "An outward pinch never lifts or closes the book")
        pager.pinch(withScale: 0.80, velocity: -0.08)
        XCTAssertTrue(reader.waitForExistence(timeout: 5), "Wait for the cancellation stage to restore the native reader")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", position), reader, timeout: 5))
        XCTAssertFalse(item("Sumi.Reader.Chapters", app).exists, "A page pinch must not tap the Chapters control")
        XCTAssertEqual(reader.value as? String, position, "Retreating from a pinch keeps the same page")
        pager.pinch(withScale: 0.55, velocity: -0.6)
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), reader))
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        let returnedBook = app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-001"]
        let sourceIsInteractive = wait(NSPredicate { _, _ in returnedBook.isHittable }, returnedBook, timeout: 5)
        attach(app, "Reader dismissed: source library before final hit-test assertion")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Reader dismissed: application accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let sourceExists = returnedBook.exists
        let sourceState = XCTAttachment(string: "exists: \(sourceExists)\nhittable: \(returnedBook.isHittable)\nframe: \(sourceExists ? String(describing: returnedBook.frame) : "not present")\nsearch field hittable: \(item("Sumi.Search.Field", app).isHittable)\nloading exists: \(item("Sumi.Book.Loading", app).exists)")
        sourceState.name = "Reader dismissed: source cover state"
        sourceState.lifetime = .keepAlways
        add(sourceState)
        let hitResult = XCTAttachment(string: "Accessibility hittable after handoff: \(sourceIsInteractive)")
        hitResult.name = "Reader dismissed: accessibility hit-test result"
        hitResult.lifetime = .keepAlways
        add(hitResult)
        returnedBook.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(reader.waitForExistence(timeout: 15),
                      "Tapping the visible returned cover must reopen it, independent of accessibility hit-test caching")
        XCTAssertTrue(app.buttons["SumiReader.Close"].waitForExistence(timeout: 5))
        attach(app, "Pinch closes the book and the returned cover opens again")
    }

    @MainActor
    func testPinchWithVisibleControlsDoesNotTapChapters() throws {
        let app = launch(diagnosePinch: true)
        defer { app.terminate() }
        let grid = item("Sumi.Grid", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-001"].tap()
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["SumiReader.Close"].waitForExistence(timeout: 5))
        let position = try XCTUnwrap(reader.value as? String)
        let portrait = item("sumi.reader.slide", app)
        let pager = portrait.exists ? portrait : item("sumi.reader.curl", app)
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        pager.pinch(withScale: 1.15, velocity: 0.3)
        XCTAssertTrue(reader.waitForExistence(timeout: 5))
        XCTAssertEqual(reader.value as? String, position, "An outward pinch with controls visible preserves the bookmark")
        XCTAssertFalse(item("Sumi.Reader.Chapters", app).exists)
        pager.pinch(withScale: 0.80, velocity: -0.08)
        XCTAssertTrue(reader.waitForExistence(timeout: 5), "Wait for the cancellation stage to restore the native reader")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", position), reader, timeout: 5))
        XCTAssertFalse(item("Sumi.Reader.Chapters", app).exists,
                       "A genuine two-finger contraction must cancel native toolbar button tracking")
        XCTAssertEqual(reader.value as? String, position)
        attach(app, "Canceled pinch with visible toolbar keeps the book and does not tap Chapters")
    }

    @MainActor
    func testSearchBookReturnsToItsExactRowWithoutKeyboardRelayout() throws {
        let app = launch()
        defer { app.terminate() }
        let grid = item("Sumi.Grid", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        try app.openHonbakoSearch()
        let field = item("Sumi.Search.Field", app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("042")
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertTrue(app.keyboards.firstMatch.exists, "Open directly from a keyboard-active search, as in normal use")
        }
        let result = app.buttons["Sumi.Search.Book.sumi-grid-preview:book-042"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        let close = app.buttons["SumiReader.Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), reader))
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Returning from reading must not automatically move the source row with the keyboard")
        let landing = result.frame
        let settledAt = Date()
        let stableRow = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = result.frame
            guard abs(frame.minX - landing.minX) < 1, abs(frame.minY - landing.minY) < 1,
                  abs(frame.width - landing.width) < 1, abs(frame.height - landing.height) < 1,
                  !app.keyboards.firstMatch.exists else { return false }
            return Date().timeIntervalSince(settledAt) >= 0.3
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [stableRow], timeout: 5), .completed,
                       "The returned row must stay at the settled destination after the close compositor handoff")
        attach(app, "Book returns to the unchanged search row")
    }

    @MainActor private func launch(diagnosePinch: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check"]
        if diagnosePinch { app.launchArguments.append("--sumi-pinch-diagnostics") }
        app.launch()
        return app
    }

    @MainActor private func item(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        if identifier == "Sumi.Search.Field" { return app.honbakoSearchField }
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor private func wait(_ predicate: NSPredicate, _ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
