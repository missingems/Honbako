import UIKit
import XCTest

final class HonbakoBookReturnInteractionTests: XCTestCase {
    @MainActor
    func testShortLandscapeBackCanCancelThenLandInTheUnchangedLibrarySlot() throws {
        continueAfterFailure = false
        let previous = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = previous }
        let grid = item("Sumi.Grid", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 20))
        let book = app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-001"]
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        let initialWindow = app.windows.element(boundBy: 0)
        XCTAssertTrue(wait { initialWindow.frame.width > initialWindow.frame.height && !book.frame.isEmpty })
        let origin = book.frame
        book.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["SumiReader.Close"].waitForExistence(timeout: 8))
        let position = reader.value as? String
        let window = try XCTUnwrap(app.windows.allElementsBoundByIndex.first {
            $0.isHittable && $0.frame.intersects(reader.frame) && $0.frame.width > $0.frame.height
        })
        let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.55))
        // Hold the partially closed stage so its real compositor frames are
        // observable in the accompanying simulator recording.
        edge.press(forDuration: 0.08,
                   thenDragTo: edge.withOffset(CGVector(dx: 20, dy: 0)),
                   withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(wait { app.buttons["SumiReader.Close"].isHittable })
        XCTAssertEqual(reader.value as? String, position)
        edge.press(forDuration: 0.08,
                   thenDragTo: edge.withOffset(CGVector(dx: 90, dy: 0)),
                   withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(wait { !reader.exists })
        XCTAssertTrue(book.waitForExistence(timeout: 8))
        let returned = book.frame
        XCTAssertEqual(returned.minX, origin.minX, accuracy: 1)
        XCTAssertEqual(returned.minY, origin.minY, accuracy: 1)
        XCTAssertEqual(returned.width, origin.width, accuracy: 1)
        XCTAssertEqual(returned.height, origin.height, accuracy: 1)
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "Library after cancelled and completed landscape return"
        attachment.lifetime = .keepAlways
        add(attachment)
        book.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        XCTAssertEqual(reader.value as? String, position, "The returned cover must reopen the same reader position")
    }

    @MainActor
    private func item(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    private func wait(_ predicate: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)], timeout: 10) == .completed
    }
}
