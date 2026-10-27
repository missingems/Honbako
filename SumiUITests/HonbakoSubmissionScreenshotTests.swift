import UIKit
import XCTest

/// Captures the genuine first-launch tutorial and reader in each supported
/// submission language. The runner installs a fresh app before each method.
final class HonbakoSubmissionScreenshotTests: XCTestCase {
    @MainActor
    func testEnglish() throws {
        try capture(language: "en", region: "en_US", locale: "en-US")
    }

    @MainActor
    func testJapanese() throws {
        try capture(language: "ja", region: "ja_JP", locale: "ja")
    }

    @MainActor
    func testSimplifiedChinese() throws {
        try capture(language: "zh-Hans", region: "zh_CN", locale: "zh-Hans")
    }

    @MainActor
    func testTraditionalChinese() throws {
        try capture(language: "zh-Hant", region: "zh_TW", locale: "zh-Hant")
    }

    @MainActor
    private func capture(language: String, region: String, locale: String) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", region]
        app.launch()
        defer { app.terminate() }

        let tutorialID = "Sumi.Grid.Book.honbako.tutorial:first-chapter"
        let book = app.buttons[tutorialID]
        XCTAssertTrue(book.waitForExistence(timeout: 30), "The original bundled tutorial must be available on first launch")
        XCTAssertFalse(item("Honbako.Library.Header.Popular", app).exists)
        let firstBook = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Sumi.Grid.Book.")).firstMatch
        XCTAssertEqual(firstBook.identifier, tutorialID)
        try attach(app, name: "\(locale)-01-library")

        book.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 30))
        let page = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@",
            ["sumi.reader.slide", "sumi.reader.curl"])).firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        let close = app.buttons["SumiReader.Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(item("Sumi.Reader.Title", app).waitForExistence(timeout: 5))
        XCTAssertTrue(item("Sumi.Reader.ThumbnailStrip", app).waitForExistence(timeout: 5))
        try attach(app, name: "\(locale)-02-reader")

        let chaptersButton = app.buttons["Sumi.Reader.ChaptersButton"]
        XCTAssertTrue(chaptersButton.waitForExistence(timeout: 5))
        chaptersButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(item("Sumi.Reader.Chapters", app).waitForExistence(timeout: 10))
        let chapterKey = "\(language)-first-chapter"
        XCTAssertTrue(app.buttons["Sumi.Reader.Chapter.\(chapterKey)"].waitForExistence(timeout: 10))
        XCTAssertTrue(item("Honbako.Reader.BundledOffline", app).waitForExistence(timeout: 5))
        let date = item("Honbako.Reader.Chapter.ReleaseDate.\(chapterKey)", app)
        let progress = item("Honbako.Reader.Chapter.Progress.\(chapterKey)", app)
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertTrue(wait(NSPredicate { _, _ in
            date.label.rangeOfCharacter(from: .decimalDigits) != nil
        }, object: date), "The chapter must show its actual release date")
        XCTAssertTrue(wait(NSPredicate { _, _ in
            progress.label.contains("1") && progress.label.contains("3")
        }, object: progress), "The tutorial chapter must show its current page and three-page total")
        try attach(app, name: "\(locale)-03-chapters")
    }

    @MainActor
    private func item(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func wait(_ predicate: NSPredicate, object: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: object)], timeout: 10) == .completed
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) throws {
        let screenshot = app.screenshot()
        let image = try XCTUnwrap(UIImage(data: screenshot.pngRepresentation))
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 1))
        let attachment = XCTAttachment(data: jpeg, uniformTypeIdentifier: "public.jpeg")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
