import UIKit
import XCTest

final class HonbakoChapterActionsInteractionTests: XCTestCase {
    @MainActor
    func testChapterPickerIsNewestFirstAndAsksAboutEarlierUnreadChapters() throws {
        let app = launch()
        defer { app.terminate() }
        let reader = try openSavedFixture(24, in: app)
        let initialPosition = try XCTUnwrap(reader.value as? String)
        let picker = try openChapters(in: app)
        let third = app.buttons["Sumi.Reader.Chapter.chapter-3"]
        let second = app.buttons["Sumi.Reader.Chapter.chapter-2"]
        let first = app.buttons["Sumi.Reader.Chapter.chapter-1"]
        for _ in 0..<4 {
            if visible(first, in: picker) && visible(third, in: picker) { break }
            picker.swipeUp()
        }
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists && third.exists)
        XCTAssertLessThan(third.frame.minY, second.frame.minY)
        XCTAssertLessThan(second.frame.minY, first.frame.minY, "The newest chapter is listed first")
        attach(app, "Chapter picker uses newest-first source order")

        // Repeated runs can resume a previous test bookmark. Pick another
        // unread chapter without clearing persistent app data to force a pass.
        let selectedNumber = initialPosition.contains("Chapter 2,") ? 3 : 2
        let selected = selectedNumber == 3 ? third : second
        centerTap(selected)
        let prompt = app.alerts["Mark Earlier Chapters as Read?"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 8), "Choosing a later chapter must ask about earlier unread chapters")
        attach(app, "Choosing a middle chapter asks before marking earlier chapters")
        centerTap(prompt.buttons["Keep Unread"])
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "Chapter \(selectedNumber), page 1"), reader, timeout: 15))
        let settled = Date()
        let noDuplicatePrompt = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !prompt.exists && Date().timeIntervalSince(settled) >= 0.6
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [noDuplicatePrompt], timeout: 5), .completed,
                       "The same choice must not be asked again after the selected chapter opens")
        attach(app, "Keep Unread opens the selected chapter without a duplicate prompt")
    }

    @MainActor
    func testNotificationProSheetStaysPresentedAndReturnsToChapterPicker() throws {
        let app = launch()
        defer { app.terminate() }
        _ = try openSavedFixture(23, in: app)
        let picker = try openChapters(in: app)
        let notify = app.buttons["Honbako.Reader.Notify"]
        for _ in 0..<3 {
            if visible(notify, in: picker) { break }
            picker.swipeUp()
        }
        XCTAssertTrue(notify.waitForExistence(timeout: 5))
        centerTap(notify)
        let proBar = app.navigationBars["Honbako Pro"]
        XCTAssertTrue(proBar.waitForExistence(timeout: 8), "A gated notification action presents the stable Pro sheet")
        let availability = app.staticTexts.matching(NSPredicate(format:
            "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
            "per month", "purchases aren", "App Store couldn")).firstMatch
        XCTAssertTrue(availability.waitForExistence(timeout: 10), "The sheet must show a monthly price or an actionable availability message")
        let presented = Date()
        let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            proBar.exists && availability.exists && Date().timeIntervalSince(presented) >= 0.8
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [stable], timeout: 5), .completed,
                       "The notification action must not instantly dismiss its purchase or unavailable-state UI")
        attach(app, "Notification Pro sheet remains visible with price or availability state")
        let done = proBar.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        centerTap(done)
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), proBar))
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Closing Pro returns to the chapter picker")
        XCTAssertTrue(app.buttons["Honbako.Reader.Notify"].exists)
        attach(app, "Closing notification Pro sheet returns to chapter options")
    }

    @MainActor
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--honbako-catalog-check", "--honbako-reader-actions-check",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(item("Sumi.Grid", app).waitForExistence(timeout: 20))
        return app
    }

    @MainActor
    private func openSavedFixture(_ number: Int, in app: XCUIApplication) throws -> XCUIElement {
        let key = String(format: "book-%03d", number)
        let identifier = "honbako-catalog-fast:\(key)"
        let grid = item("Sumi.Grid", app)
        try app.openHonbakoSearch()
        let search = item("Sumi.Search.Field", app)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText(String(format: "%03d", number))
        let result = app.buttons["Sumi.Search.Book.\(identifier)"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        let add = app.buttons["Sumi.Search.Add.\(identifier)"]
        if add.exists {
            centerTap(add)
            let saved = app.buttons["Sumi.Grid.Book.\(identifier)"]
            XCTAssertTrue(saved.waitForExistence(timeout: 10))
            centerTap(saved)
        } else { centerTap(result) }
        let reader = item("Sumi.DirectReader", app)
        let previousPrompt = app.alerts["Mark Earlier Chapters as Read?"]
        XCTAssertTrue(wait(NSPredicate { _, _ in reader.exists || previousPrompt.exists }, app, timeout: 20))
        if previousPrompt.exists { centerTap(previousPrompt.buttons["Keep Unread"]) }
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "Chapter "), reader))
        return reader
    }

    @MainActor
    private func openChapters(in app: XCUIApplication) throws -> XCUIElement {
        XCTAssertTrue(item("Sumi.Reader.Title", app).waitForExistence(timeout: 10))
        let button = app.buttons["Sumi.Reader.ChaptersButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        centerTap(button)
        let picker = item("Sumi.Reader.Chapters", app)
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        return picker
    }

    @MainActor
    private func visible(_ element: XCUIElement, in container: XCUIElement) -> Bool {
        guard element.exists, element.frame.width > 1, element.frame.height > 1 else { return false }
        let intersection = container.frame.intersection(element.frame)
        return !intersection.isNull && intersection.height >= min(40, element.frame.height)
    }

    @MainActor
    private func centerTap(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @MainActor
    private func item(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        if identifier == "Sumi.Search.Field" { return app.honbakoSearchField }
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func wait(_ predicate: NSPredicate, _ object: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: object)], timeout: timeout) == .completed
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
