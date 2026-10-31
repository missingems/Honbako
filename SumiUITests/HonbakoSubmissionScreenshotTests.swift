import UIKit
import XCTest

/// Captures the genuine first-launch tutorial and reader in each supported
/// submission language. Prepare the named disposable capture simulator with
/// scripts/prepare_honbako_screenshot_library.py before each locale.
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
    func testIPadPortraitLibraryEnglish() throws {
        try capture(language: "en", region: "en_US", locale: "en-US", libraryOnly: true)
    }

    @MainActor
    func testIPadPortraitLibraryJapanese() throws {
        try capture(language: "ja", region: "ja_JP", locale: "ja", libraryOnly: true)
    }

    @MainActor
    func testIPadPortraitLibrarySimplifiedChinese() throws {
        try capture(language: "zh-Hans", region: "zh_CN", locale: "zh-Hans", libraryOnly: true)
    }

    @MainActor
    func testIPadPortraitLibraryTraditionalChinese() throws {
        try capture(language: "zh-Hant", region: "zh_TW", locale: "zh-Hant", libraryOnly: true)
    }

    @MainActor
    private func capture(language: String, region: String, locale: String, libraryOnly: Bool = false) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", region,
                               "-Honbako.Welcome.CompletedVersion", "2",
                               "-General.icloudSync", "NO",
                               "-Honbako.Reader.ShowCoverDisplay", "NO"]
        app.launch()
        defer { app.terminate() }

        let tutorialID = "Sumi.Grid.Book.honbako.tutorial:first-chapter"
        let book = app.buttons[tutorialID]
        let grid = item("Sumi.Grid", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 30))
        XCTAssertTrue(wait(NSPredicate { _, _ in
            (grid.value as? String)?.contains("55") == true
        }, object: grid), "The screenshot library contains 50 real original-art portfolios and five bundled guides")
        XCTAssertFalse(item("Honbako.Library.Header.Popular", app).exists)
        XCTAssertTrue(wait(NSPredicate { _, _ in
            app.windows.firstMatch.frame.width < app.windows.firstMatch.frame.height
        }, object: grid), "The library must be visibly upright portrait before capture")
        try attach(app, name: "\(locale)-01-library")
        if libraryOnly { return }

        // Native cover views can report a false XCTest hittable result even
        // while the original tutorial is visibly first in the library. Use its
        // actual element geometry for the same tap a reader makes.
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 30))
        XCUIDevice.shared.orientation = .portrait
        let page = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@",
            ["sumi.reader.slide", "sumi.reader.curl"])).firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        let close = app.buttons["SumiReader.Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Sumi.Reader.Navigation"].waitForExistence(timeout: 5))
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
            progress.label.contains("1") && progress.label.contains("6")
        }, object: progress), "The tutorial chapter must show its current page and six-page total")
        let current = app.buttons["Sumi.Reader.Chapter.\(chapterKey)"]
        XCTAssertTrue(current.isHittable, "The current chapter must scroll into view automatically")
        XCTAssertTrue(current.isSelected, "The current chapter must be highlighted as selected")
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
        // Let native image-load fades and rotation settle in the app process.
        Thread.sleep(forTimeInterval: 1)
        let screenshot = app.screenshot()
        let native = try XCTUnwrap(UIImage(data: screenshot.pngRepresentation))
        // Normalize the native UIImage orientation before JPEG encoding. This is
        // the same screenshot pixel content, with no resize, crop or UI redraw.
        let format = UIGraphicsImageRendererFormat()
        format.scale = native.scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: native.size, format: format).image { _ in
            native.draw(at: .zero)
        }
        let pixels = try XCTUnwrap(image.cgImage)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertEqual(pixels.width, 2064)
            XCTAssertEqual(pixels.height, 2752)
        } else {
            XCTAssertEqual(pixels.width, 1320, "The release set uses the required large iPhone display")
            XCTAssertEqual(pixels.height, 2868)
        }
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 1))
        let attachment = XCTAttachment(data: jpeg, uniformTypeIdentifier: "public.jpeg")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
