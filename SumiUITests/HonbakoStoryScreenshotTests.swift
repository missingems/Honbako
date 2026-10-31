import UIKit
import XCTest

/// Select an actual story translation explicitly so a previous capture's
/// remembered chapter language cannot leak into another storefront's artwork.
final class HonbakoStoryScreenshotTests: XCTestCase {
    @MainActor func testEnglish() throws { try capture(language: "en", region: "en_US", locale: "en-US") }
    @MainActor func testJapanese() throws { try capture(language: "ja", region: "ja_JP", locale: "ja") }
    @MainActor func testSimplifiedChinese() throws { try capture(language: "zh-Hans", region: "zh_CN", locale: "zh-Hans") }
    @MainActor func testTraditionalChinese() throws { try capture(language: "zh-Hant", region: "zh_TW", locale: "zh-Hant") }
    @MainActor func testIPadLibraryCompositions() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        for (language, region, locale) in [("en", "en_US", "en-US"), ("ja", "ja_JP", "ja"), ("zh-Hans", "zh_CN", "zh-Hans"), ("zh-Hant", "zh_TW", "zh-Hant")] {
            let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
            app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", region,
                "-AppleInterfaceStyle", "Dark", "-Honbako.Welcome.CompletedVersion", "2",
                "-General.icloudSync", "NO", "-Honbako.Reader.ShowCoverDisplay", "NO"]
            app.launch()
            XCTAssertTrue(item("Sumi.Grid", app).waitForExistence(timeout: 20))
            // One native scroll keeps complete rows visible; a second reaches
            // the collection's end and exposes the intentional control margin.
            app.swipeUp()
            attach(app, "\(locale)-library")
            app.terminate()
        }
    }
    @MainActor private func capture(language: String, region: String, locale: String) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", region,
            "-AppleInterfaceStyle", "Dark", "-Honbako.Welcome.CompletedVersion", "2",
            "-General.icloudSync", "NO", "-Honbako.Reader.ShowCoverDisplay", "NO"]
        app.launch(); defer { app.terminate() }
        let book = app.buttons["Sumi.Grid.Book.honbako.tutorial:first-chapter"]
        XCTAssertTrue(book.waitForExistence(timeout: 20))
        for _ in 0..<8 { if book.isHittable { break }; app.swipeDown() }
        book.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let chapters = app.buttons["Sumi.Reader.ChaptersButton"]
        XCTAssertTrue(chapters.waitForExistence(timeout: 15)); chapters.tap()
        let desired = app.buttons["Sumi.Reader.Chapter.\(language)-first-chapter"]
        if desired.exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        } else {
            let picker = item("Sumi.Reader.Language", app)
            for _ in 0..<7 { if picker.isHittable { break }; app.swipeDown() }
            XCTAssertTrue(picker.isHittable); picker.tap()
            let name = try XCTUnwrap(Locale(identifier: region).localizedString(forIdentifier: language))
            let option = app.buttons[name]
            XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
            XCTAssertTrue(wait { !self.item("Sumi.Reader.Chapters", app).exists })
        }
        let first = item("Sumi.Reader.Thumbnail.1", app)
        if !first.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.53, dy: 0.5)).tap() }
        XCTAssertTrue(first.waitForExistence(timeout: 5)); first.tap()
        if !chapters.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.53, dy: 0.5)).tap() }
        attach(app, "\(locale)-reader")
        app.buttons["SumiReader.Close"].tap()
        XCTAssertTrue(item("Sumi.Grid", app).waitForExistence(timeout: 10))
        app.swipeUp(); app.swipeUp()
        attach(app, "\(locale)-library")
    }
    @MainActor private func item(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    @MainActor private func wait(_ check: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in check() }, object: nil)], timeout: 12) == .completed
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1.5)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
