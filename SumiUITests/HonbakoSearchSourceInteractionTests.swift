import UIKit
import XCTest

final class HonbakoSearchSourceInteractionTests: XCTestCase {
    @MainActor
    func testFastSourceAppearsWhileAnotherSourceLoadsAndSharedTitlesStayInBothSections() throws {
        let app = launch()
        defer { app.terminate() }
        try search("Shared", in: app)
        let fast = app.buttons["Sumi.Search.Book.honbako-catalog-fast:shared-title"]
        let slow = app.buttons["Sumi.Search.Book.honbako-catalog-slow:shared-title"]
        XCTAssertTrue(fast.waitForExistence(timeout: 3), "A ready source must not wait for the slow catalog")
        XCTAssertTrue(item("Honbako.Search.SourceHeader.honbako-catalog-fast", app).exists)
        XCTAssertTrue(item("Honbako.Search.Loading", app).exists,
                      "The first complete row is usable while other sources are still searching")
        XCTAssertFalse(slow.exists)
        XCTAssertTrue(slow.waitForExistence(timeout: 8))
        XCTAssertTrue(fast.exists, "The first source edition must stay visible when another provider returns the same title")
        XCTAssertTrue(item("Honbako.Search.SourceHeader.honbako-catalog-slow", app).exists)
        XCTAssertEqual(fast.label, slow.label)
        attach(app, "Search sections retain both source editions")
    }

    @MainActor
    func testSearchSourceHeaderStaysPinnedWhileItsRowsScroll() throws {
        let app = launch()
        defer { app.terminate() }
        try search("Fixture", in: app)
        let header = item("Honbako.Search.SourceHeader.honbako-catalog-fast", app)
        let first = app.buttons["Sumi.Search.Book.honbako-catalog-fast:book-001"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(header.exists)
        let originalHeader = header.frame
        let originalRow = first.frame
        let results = item("Honbako.Search.Results", app)
        XCTAssertTrue(results.exists)
        results.swipeUp()
        XCTAssertTrue(header.exists)
        XCTAssertEqual(header.frame.minY, originalHeader.minY, accuracy: 1,
                       "Source identity stays pinned at the top of the result list")
        XCTAssertTrue(!first.isHittable || abs(first.frame.minY - originalRow.minY) > 10,
                      "Rows must actually move below the pinned source header")
        attach(app, "Pinned source header while result rows scroll")
    }

    @MainActor
    func testPopularIsAbsentWithoutAddedSources() throws {
        let app = launch(empty: true)
        defer { app.terminate() }
        XCTAssertFalse(item("Honbako.Library.Header.Popular", app).exists)
        XCTAssertFalse(item("Honbako.Library.Header.Recommendations", app).exists)
        try search("Manga", in: app)
        XCTAssertTrue(app.staticTexts["Connect a Library"].waitForExistence(timeout: 5))
        XCTAssertFalse(item("Honbako.Library.Header.Popular", app).exists)
        attach(app, "No automatic popular catalog without sources")
    }

    @MainActor
    func testLibraryHasNoPopularAndSearchOpensTheProvidersActualCoverAndReader() throws {
        let app = launch()
        defer { app.terminate() }
        XCTAssertFalse(item("Honbako.Library.Header.Popular", app).exists,
                       "Configured sources must not repopulate the removed automatic catalog")
        try search("Shared Manga", in: app)
        let cover = app.buttons["Sumi.Search.Book.honbako-catalog-fast:shared-title"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        let artwork = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.hasColoredArtwork(cover.screenshot().image)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [artwork], timeout: 8), .completed,
                       "The search row must contain the source's real colored cover rather than a text placeholder")
        attach(app, "Search cover loaded through the source-aware renderer")
        cover.tap()
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 20))
        let firstPage = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "Chapter 1, page 1"), object: reader)
        XCTAssertEqual(XCTWaiter.wait(for: [firstPage], timeout: 8), .completed)
        attach(app, "Search source book opens directly on its first chapter")
    }

    @MainActor
    private func launch(empty: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = [empty ? "--honbako-catalog-empty" : "--honbako-catalog-check"]
        app.launch()
        XCTAssertTrue(item("Sumi.Grid", app).waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func search(_ text: String, in app: XCUIApplication) throws {
        item("Sumi.Grid", app).swipeDown()
        let field = item("Sumi.Search.Field", app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText(text)
    }

    @MainActor
    private func item(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func hasColoredArtwork(_ image: UIImage) -> Bool {
        guard let image = image.cgImage else { return false }
        var pixels = [UInt8](repeating: 0, count: 24 * 24 * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 24, height: 24,
                bitsPerComponent: 8, bytesPerRow: 24 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 24, height: 24))
            return true
        }
        guard rendered else { return false }
        let colored = stride(from: 0, to: pixels.count, by: 4).filter { index in
            let channels = [pixels[index], pixels[index + 1], pixels[index + 2]]
            return Int(channels.max() ?? 0) - Int(channels.min() ?? 0) > 60
        }.count
        // A fixed cover occupies only part of a Search row; the surrounding
        // labels are intentionally neutral and must not count as artwork.
        return colored > 24 * 24 / 20
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
