import UIKit
import XCTest

final class SumiReaderPolishInteractionTests: XCTestCase {
    @MainActor
    func testTapShowsTitleScrubKeepsNavigationAndChapterMenuRemainsReadable() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check", "--sumi-grid-reading-mode=rtl", "--sumi-grid-languages"]
        app.launch()
        defer { app.terminate() }
        let book = app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-001"]
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        book.tap()
        let reader = item("Sumi.DirectReader", app)
        let close = app.buttons["SumiReader.Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 20))
        let title = item("Sumi.Reader.Title", app)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Fixture Manga 001")
        let page = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@",
            ["sumi.reader.slide", "sumi.reader.curl"])).firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), title))
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45)).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        attach(app, "Manga title appears with the reader controls")

        let strip = item("Sumi.Reader.ThumbnailStrip", app)
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        let firstPosition = reader.value as? String
        // Hold the real native drag long enough to inspect its lifted glass in
        // the accompanying simulator recording, then verify normal navigation.
        let verticalStrip = strip.frame.height > strip.frame.width
        let start = verticalStrip ? CGVector(dx: 0.5, dy: 0.72) : CGVector(dx: 0.72, dy: 0.5)
        let end = verticalStrip ? CGVector(dx: 0.5, dy: 0.18) : CGVector(dx: 0.18, dy: 0.5)
        strip.coordinate(withNormalizedOffset: start)
            .press(forDuration: 0.1,
                thenDragTo: strip.coordinate(withNormalizedOffset: end),
                withVelocity: .slow, thenHoldForDuration: 2)
        XCTAssertTrue(wait(NSPredicate { _, _ in (reader.value as? String) != firstPosition }, reader))
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), item("Sumi.Reader.ScrubPreview", app)))

        if !close.isHittable {
            page.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.45)).tap()
        }
        let chapters = app.buttons["Sumi.Reader.ChaptersButton"]
        XCTAssertTrue(chapters.waitForExistence(timeout: 5))
        chapters.tap()
        XCTAssertTrue(item("Sumi.Reader.Chapters", app).waitForExistence(timeout: 5))
        XCTAssertTrue(item("Sumi.Reader.Language", app).exists)
        attach(app, "Readable chapter menu over page artwork")
    }

    @MainActor private func item(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor private func wait(_ predicate: NSPredicate, _ element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10) == .completed
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
