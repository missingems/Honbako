import StoreKit
import StoreKitTest
import UIKit
import XCTest

/// Marketing captures of the submitted 0.2.0 UI, with owned sample books only.
/// No production pairing or user library is used. Pro is verified through a
/// no-charge local StoreKit transaction, without an entitlement bypass.
final class HonbakoFeatureScreenshotTests: XCTestCase {
    private var session: SKTestSession?
    @MainActor func testEnglish() async throws { try await capture(language: "en", region: "en_US", locale: "en-US") }
    @MainActor func testJapanese() async throws { try await capture(language: "ja", region: "ja_JP", locale: "ja") }
    @MainActor func testSimplifiedChinese() async throws { try await capture(language: "zh-Hans", region: "zh_CN", locale: "zh-Hans") }
    @MainActor func testTraditionalChinese() async throws { try await capture(language: "zh-Hant", region: "zh_TW", locale: "zh-Hant") }

    @MainActor func testCoachingEnglish() throws { try coaching(language: "en", locale: "en-US") }
    @MainActor func testCoachingJapanese() throws { try coaching(language: "ja", locale: "ja") }
    @MainActor func testCoachingSimplifiedChinese() throws { try coaching(language: "zh-Hans", locale: "zh-Hans") }
    @MainActor func testCoachingTraditionalChinese() throws { try coaching(language: "zh-Hant", locale: "zh-Hant") }
    @MainActor private func coaching(language: String, locale: String) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check", "--sumi-grid-reading-mode=rtl",
            "--honbako-page-access-check", "--honbako-owned-marketing-sample",
            "-AppleLanguages", "(\(language))", "-AppleInterfaceStyle", "Dark"]
        app.launch(); defer { app.terminate() }
        let book = app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-002"]
        XCTAssertTrue(book.waitForExistence(timeout: 20)); book.tap()
        XCTAssertTrue(item("Sumi.DirectReader", app).waitForExistence(timeout: 15))
        let note = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@", "Nori is", "ノリは", "诺里是", "諾里是")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 20))
        attach(app, "\(locale)-coaching")
    }

    @MainActor private func capture(language: String, region: String, locale: String) async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let configuration = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "HonbakoPro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: configuration)
        session = store
        store.resetToDefaultState(); store.disableDialogs = true; store.clearTransactions()
        let purchase = try await store.buyProduct(identifier: "com.missingems.honbaku.pro")
        XCTAssertEqual(purchase.environment, .xcode)
        await purchase.finish()
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", region,
            "-AppleInterfaceStyle", "Dark", "-Honbako.Welcome.CompletedVersion", "2",
            "-General.icloudSync", "NO", "-Honbako.Reader.ShowCoverDisplay", "NO"]
        app.launch()
        defer { app.terminate(); store.clearTransactions(); session = nil }
        XCTAssertTrue(item("Sumi.Grid", app).waitForExistence(timeout: 30))
        attach(app, "\(locale)-library")

        let settings = app.buttons["Honbako.Library.Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        let extensions = item("Honbako.Settings.Extensions", app)
        reveal(extensions, app)
        XCTAssertTrue(extensions.exists, "The 0.2.0 external-sources feature must be compiled in")
        attach(app, "\(locale)-sources")
        extensions.tap()
        XCTAssertTrue(item("Honbako.Extensions.Repositories", app).waitForExistence(timeout: 10))
        attach(app, "\(locale)-extensions")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let mcp = item("Honbako.Automation", app)
        reveal(mcp, app); mcp.tap()
        XCTAssertTrue(item("Honbako.MCP.Mode", app).waitForExistence(timeout: 10))
        XCTAssertTrue(item("Honbako.MCP.URL", app).waitForExistence(timeout: 15))
        attach(app, "\(locale)-ai-connect")
        let permissions = item("Honbako.MCP.Permission.Annotations", app)
        reveal(permissions, app)
        XCTAssertTrue(permissions.exists)
        attach(app, "\(locale)-ai-permissions")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(item("Sumi.Grid", app).waitForExistence(timeout: 10))

        let book = app.buttons["Sumi.Grid.Book.honbako.tutorial:first-chapter"]
        reveal(book, app, down: true); XCTAssertTrue(book.exists)
        book.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(item("Sumi.DirectReader", app).waitForExistence(timeout: 20))
        attach(app, "\(locale)-reader")
        let fourthPage = item("Sumi.Reader.Thumbnail.4", app)
        if fourthPage.waitForExistence(timeout: 5) { fourthPage.tap() }
        attach(app, "\(locale)-reader-controls")
        let close = app.buttons["SumiReader.Close"]
        show(close, app); close.tap()
        XCTAssertTrue(item("Sumi.Grid", app).waitForExistence(timeout: 10))
        let japanese = app.buttons["Sumi.Grid.Book.honbako.tutorial:guide-japanese"]
        reveal(japanese, app, down: true)
        XCTAssertTrue(japanese.exists)
        japanese.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(item("Sumi.DirectReader", app).waitForExistence(timeout: 15))
        let chapters = app.buttons["Sumi.Reader.ChaptersButton"]
        show(chapters, app); chapters.tap()
        let picker = item("Sumi.Reader.Language", app)
        reveal(picker, app, down: true)
        if language != "ja" {
            XCTAssertTrue(picker.exists)
            picker.tap()
            let japaneseOption = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@ OR label == %@ OR label == %@", "日本語", "Japanese", "日语", "日文")).firstMatch
            XCTAssertTrue(japaneseOption.waitForExistence(timeout: 5))
            japaneseOption.tap()
            // Choosing an available translation resumes it immediately.
            XCTAssertTrue(wait { !self.item("Sumi.Reader.Chapters", app).exists })
            show(chapters, app); chapters.tap()
        }
        let toggle = app.switches["Honbako.Reader.Japanese.ToggleInChapters"]
        reveal(toggle, app, down: true)
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if toggle.value as? String != "1" {
            let control = toggle.switches.firstMatch
            if control.exists { control.tap() } else { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5)).tap() }
        }
        XCTAssertTrue(wait { toggle.value as? String == "1" })
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let secondPage = item("Sumi.Reader.Thumbnail.2", app)
        show(secondPage, app); XCTAssertTrue(secondPage.waitForExistence(timeout: 10)); secondPage.tap()
        let annotation = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Honbako.Reader.Japanese.Word.")).firstMatch
        XCTAssertTrue(annotation.waitForExistence(timeout: 30))
        // Keep native chrome for context; the sample page is the bundled original guide.
        attach(app, "\(locale)-japanese")
    }
    @MainActor private func item(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    @MainActor private func wait(_ check: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in check() }, object: nil)], timeout: 12) == .completed
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication, down: Bool = false) {
        for _ in 0..<9 {
            if element.exists {
                let f = element.frame, w = app.windows.firstMatch.frame
                if element.isHittable && f.midY > 100 && f.midY < w.maxY - 70 { return }
            }
            if down { app.swipeDown() } else { app.swipeUp() }
        }
    }
    @MainActor private func show(_ control: XCUIElement, _ app: XCUIApplication) {
        if !control.exists || !control.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.53, dy: 0.48)).tap() }
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
