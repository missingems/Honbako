import StoreKit
import StoreKitTest
import UIKit
import XCTest

/// Real native UI with publisher-licensed manga, isolated from the user library.
final class HonbakoLicensedMangaScreenshotTests: XCTestCase {
    @MainActor func testEnglish() async throws { try await capture(language: "en", region: "en_US", locale: "en-US") }
    @MainActor func testJapanese() async throws { try await capture(language: "ja", region: "ja_JP", locale: "ja") }
    @MainActor func testSimplifiedChinese() async throws { try await capture(language: "zh-Hans", region: "zh_CN", locale: "zh-Hans") }
    @MainActor func testTraditionalChinese() async throws { try await capture(language: "zh-Hant", region: "zh_TW", locale: "zh-Hant") }

    @MainActor private func capture(language: String, region: String, locale: String) async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let configuration = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "HonbakoPro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: configuration)
        store.resetToDefaultState(); store.disableDialogs = true; store.clearTransactions()
        let purchase = try await store.buyProduct(identifier: "com.missingems.honbaku.pro")
        XCTAssertEqual(purchase.environment, .xcode)
        await purchase.finish()
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        let args = ["--sumi-grid-check", "--sumi-grid-reading-mode=rtl", "--honbako-licensed-marketing-sample",
            "-AppleLanguages", "(\(language))", "-AppleLocale", region,
            "-AppleInterfaceStyle", "Dark", "-Honbako.Welcome.CompletedVersion", "2",
            "-General.icloudSync", "NO", "-Honbako.Reader.ShowCoverDisplay", "NO"]
        app.launchArguments = args + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        defer { app.terminate(); store.clearTransactions() }
        XCTAssertTrue(item("Sumi.Grid", app).waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-001"].waitForExistence(timeout: 10))
        attach(app, "\(locale)-library")
        app.terminate()
        app.launchArguments = args
        app.launch()
        let settings = app.buttons["Honbako.Library.Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        let extensions = item("Honbako.Settings.Extensions", app)
        for _ in 0..<6 { if extensions.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(extensions.exists)
        attach(app, "\(locale)-sources")
        let mcp = item("Honbako.Automation", app)
        for _ in 0..<6 { if mcp.isHittable { break }; app.swipeUp() }
        mcp.tap()
        XCTAssertTrue(item("Honbako.MCP.Mode", app).waitForExistence(timeout: 10))
        let permissions = item("Honbako.MCP.Permission.Annotations", app)
        for _ in 0..<7 { if permissions.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(permissions.exists)
        attach(app, "\(locale)-ai-permissions")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let book = app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-001"]
        XCTAssertTrue(book.waitForExistence(timeout: 20)); book.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(item("Sumi.DirectReader", app).waitForExistence(timeout: 20))
        attach(app, "\(locale)-reader")
        let chapters = app.buttons["Sumi.Reader.ChaptersButton"]
        show(chapters, app); chapters.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(item("Sumi.Reader.Chapters", app).waitForExistence(timeout: 10))
        let toggle = app.switches["Honbako.Reader.Japanese.ToggleInChapters"]
        for _ in 0..<5 {
            if toggle.exists && toggle.isHittable { break }
            item("Sumi.Reader.Chapters", app).swipeDown()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if toggle.value as? String != "1" {
            let control = toggle.switches.firstMatch
            if control.exists { control.tap() } else { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5)).tap() }
        }
        XCTAssertTrue(wait { toggle.value as? String == "1" })
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let annotation = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Honbako.Reader.Japanese.Word.")).firstMatch
        XCTAssertTrue(annotation.waitForExistence(timeout: 40))
        attach(app, "\(locale)-japanese")
        app.terminate()
        app.launchArguments = args + ["--honbako-page-access-check"]
        app.launch()
        XCTAssertTrue(book.waitForExistence(timeout: 20)); book.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(item("Sumi.DirectReader", app).waitForExistence(timeout: 20))
        let note = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@", "Akari is", "アカリは", "小光正在", "小光正在")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 25))
        attach(app, "\(locale)-coaching")
    }
    @MainActor private func item(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    @MainActor private func wait(_ check: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in check() }, object: nil)], timeout: 15) == .completed
    }
    @MainActor private func show(_ control: XCUIElement, _ app: XCUIApplication) {
        if !control.exists || !control.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.53, dy: 0.48)).tap() }
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<7 { if element.isHittable { return }; app.swipeUp() }
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1.5)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
