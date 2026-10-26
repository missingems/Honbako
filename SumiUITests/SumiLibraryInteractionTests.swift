import XCTest

/// Real touches against generated books; the user's library is never opened.
final class SumiLibraryInteractionTests: XCTestCase {
    @MainActor
    func testFloorDragAndNativeBookZoom() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-library-check", "--sumi-library-reset-placement"]
        app.launch()
        defer { app.terminate() }
        let table = app.otherElements["Sumi.Library.Tabletop"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 12), app.debugDescription)
        assertFloorHasNoExtraControls(app)
        // app.screenshot() can capture the inactive outer display on an open Duo.
        let landscape = table.frame.width > table.frame.height
        let surface = try XCTUnwrap(app.windows.allElementsBoundByIndex.filter {
            $0.isHittable && !$0.frame.isEmpty && ($0.frame.width > $0.frame.height) == landscape
        }.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        let settled = NSPredicate(format: "value == %@", "Books settled")
        XCTAssertTrue(wait(for: settled, on: table, timeout: 14), "The initial book pile never settled")
        let ids = (0..<8).map { "Sumi.Library.Book.sumi-preview:book-\($0)" }
        let frames = ids.map { app.buttons[$0].firstMatch.frame }
        let book = app.buttons[ids[7]].firstMatch
        XCTAssertTrue(book.exists && book.isHittable)
        let start = book.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let end = start.withOffset(CGVector(dx: -85, dy: -55))
        start.press(forDuration: 0.12, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertFalse(app.buttons["SumiCloseBook"].exists, "Dragging unexpectedly opened a book")
        XCTAssertTrue(wait(for: settled, on: table, timeout: 14), "Released books never came to rest")
        let movement = ids.enumerated().map { index, id in
            let after = app.buttons[id].firstMatch.frame
            return hypot(after.midX - frames[index].midX, after.midY - frames[index].midY)
        }.max() ?? 0
        XCTAssertGreaterThan(movement, 18, "The real drag did not move any 3D book")
        assertFloorHasNoExtraControls(app)
        attach(surface.screenshot(), named: "Floor books after a real drag and physics settle")

        // Tap the actual floor book. There is no shelf or alternate layout in
        // this path; save its visible source region for the return comparison.
        XCTAssertTrue(book.isHittable)
        XCTAssertTrue(book.label.contains("The Climber"))
        let selectedBookLabel = book.label
        let sourceFrame = book.frame
        XCTAssertGreaterThan(sourceFrame.width, 20)
        XCTAssertGreaterThan(sourceFrame.height, 20)
        book.tap()
        let close = app.buttons["SumiCloseBook"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 6), app.debugDescription)
        XCTAssertTrue(app.buttons["SumiReadBook"].waitForExistence(timeout: 6))
        let openedBook = app.descendants(matching: .any).matching(identifier: "Sumi.Book.Open.sumi-preview:book-7").firstMatch
        XCTAssertTrue(openedBook.waitForExistence(timeout: 5), "A direct floor tap opened a different book")
        attach(surface.screenshot(), named: "Book expanded directly from the floor")

        // UIKit hides the source proxy during zoom. Record the target only if
        // its container is exposed without hiding its useful accessibility children.
        let target = app.descendants(matching: .any).matching(identifier: "Sumi.Book.ZoomTarget").firstMatch
        let targetFrame = target.exists && !target.frame.isEmpty ? target.frame : nil
        if let targetFrame {
            XCTAssertGreaterThan(targetFrame.width * targetFrame.height,
                                 sourceFrame.width * sourceFrame.height,
                                 "The expanded book did not grow beyond its floor source")
        }
        close.tap()
        XCTAssertTrue(wait(for: NSPredicate(format: "exists == false"), on: close, timeout: 6), "The expanded book did not close")
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        XCTAssertTrue(wait(for: settled, on: table, timeout: 14))
        XCTAssertTrue(book.exists && book.isHittable)
        let restoredFrame = book.frame
        let tolerance = max(6, min(sourceFrame.width, sourceFrame.height) * 0.08)
        XCTAssertEqual(restoredFrame.midX, sourceFrame.midX, accuracy: tolerance, "Closing reset the book's floor position")
        XCTAssertEqual(restoredFrame.midY, sourceFrame.midY, accuracy: tolerance, "Closing reset the book's floor position")
        XCTAssertEqual(restoredFrame.width, sourceFrame.width, accuracy: tolerance)
        XCTAssertEqual(restoredFrame.height, sourceFrame.height, accuracy: tolerance)
        assertFloorHasNoExtraControls(app)
        attach(surface.screenshot(), named: "Closing returns to the same floor arrangement")

        var evidence: [String: Any] = [
            "selectedFloorBook": selectedBookLabel,
            "sourceFloorFrame": rect(sourceFrame),
            "restoredFloorFrame": rect(restoredFrame),
            "restorationTolerancePoints": Double(tolerance),
            "targetExposedToAccessibility": targetFrame != nil
        ]
        if let targetFrame { evidence["expandedTargetFrame"] = rect(targetFrame) }
        else { evidence["expandedTargetFrame"] = NSNull() }
        let data = try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
        let frameEvidence = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        frameEvidence.name = "Floor source, expanded target, and restored book frames"
        frameEvidence.lifetime = .keepAlways
        add(frameEvidence)
    }

    @MainActor
    private func assertFloorHasNoExtraControls(_ app: XCUIApplication) {
        for title in ["Layout", "Shelved", "Scattered", "Zoom in", "Zoom out", "Show all books"] {
            XCTAssertFalse(app.buttons[title].exists, "The floor still exposes \(title)")
        }
        for identifier in ["Sumi.Library.Zoomin", "Sumi.Library.Zoomout", "Sumi.Library.Showallbooks"] {
            XCTAssertFalse(app.buttons[identifier].exists, "The floor still exposes a zoom button")
        }
        XCTAssertFalse(app.staticTexts["Library"].exists, "The floor still has an extra Library title")
    }

    private func rect(_ frame: CGRect) -> [Double] {
        [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)]
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func wait(for predicate: NSPredicate, on object: Any, timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: object)], timeout: timeout) == .completed
    }
}
