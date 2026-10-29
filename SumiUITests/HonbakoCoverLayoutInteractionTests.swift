import UIKit
import XCTest

final class HonbakoCoverLayoutInteractionTests: XCTestCase {
    @MainActor
    func testMixedAspectCoversFillTheirSlotsWithoutDistortingCircularArtwork() throws {
        let app = launch(checkCoverLayout: true)
        defer { app.terminate() }
        XCTAssertFalse(item("Honbako.Library.Header.Popular", app).exists)
        try app.openHonbakoSearch()
        let field = item("Sumi.Search.Field", app)
        guard field.waitForExistence(timeout: 5), app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            XCTFail("Search must expose the configured source catalog")
            return
        }
        var previousQuery = ""
        for (key, title) in [("shared-title", "Shared Manga"), ("book-001", "Fixture Manga 001"),
                             ("book-002", "Fixture Manga 002")] {
            field.tap()
            if !previousQuery.isEmpty {
                // Tapping a native text field can place its caret in the middle.
                // Its clear button replaces the entire query independently of
                // caret position and the system's localized button label.
                let clear = field.buttons.firstMatch
                guard clear.waitForExistence(timeout: 3) else {
                    XCTFail("The native Search clear control is unavailable for \(previousQuery)")
                    return
                }
                clear.tap()
            }
            field.typeText(title)
            previousQuery = title
            let cover = app.buttons["Sumi.Search.Book.honbako-catalog-fast:\(key)"]
            guard cover.waitForExistence(timeout: 5) else {
                XCTFail("Missing cover: \(title); Search value: \(String(describing: field.value))")
                continue
            }
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.searchCover(in: cover.screenshot().image).flatMap(self.marker(in:)) != nil
            }, object: nil)
            guard XCTWaiter.wait(for: [loaded], timeout: 8) == .completed,
                  let print = searchCover(in: cover.screenshot().image), let marker = marker(in: print) else {
                XCTFail("The source artwork did not load for \(title)")
                continue
            }
            XCTAssertEqual(marker.bounds.width / marker.bounds.height, 1, accuracy: 0.08,
                           "The circular artwork must stay circular for \(title)")
            XCTAssertGreaterThan(marker.coloredFraction, 0.85,
                                 "Cover artwork must fill the slot without letterboxing for \(title)")
        }
        attach(app, "Wide square and tall Search covers preserve circular artwork")
    }

    @MainActor
    func testSourceHeaderBlurSpansTheSearchWidthAndStaysPinned() throws {
        let app = launch()
        defer { app.terminate() }
        try app.openHonbakoSearch()
        let field = item("Sumi.Search.Field", app)
        guard field.waitForExistence(timeout: 5), app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            XCTFail("Search and keyboard must appear")
            return
        }
        field.typeText("Fixture")
        let header = item("Honbako.Search.SourceHeader.honbako-catalog-fast", app)
        guard header.waitForExistence(timeout: 5) else { XCTFail("Source header is missing"); return }
        let results = item("Honbako.Search.Results", app)
        guard results.exists else { XCTFail("Search result viewport is missing"); return }
        let original = header.frame
        XCTAssertEqual(header.frame.minX, results.frame.minX, accuracy: 1,
                       "The section background reaches the search's leading edge")
        XCTAssertEqual(header.frame.maxX, results.frame.maxX, accuracy: 1,
                       "The section background reaches the search's trailing edge")
        results.swipeUp()
        XCTAssertTrue(header.exists)
        XCTAssertEqual(header.frame.minY, original.minY, accuracy: 1,
                       "The full-width source header stays pinned while rows scroll")
        XCTAssertEqual(header.frame.minX, results.frame.minX, accuracy: 1)
        XCTAssertEqual(header.frame.maxX, results.frame.maxX, accuracy: 1)
        attach(app, "Blurred source section spans the search panel edges")
    }

    @MainActor
    private func launch(checkCoverLayout: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--honbako-catalog-check"]
        if checkCoverLayout { app.launchArguments.append("--honbako-cover-layout-check") }
        app.launch()
        XCTAssertTrue(item("Sumi.Grid", app).waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func item(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        if identifier == "Sumi.Search.Field" { return app.honbakoSearchField }
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private struct Marker {
        let bounds: CGRect
        let coloredFraction: Double
    }

    /// Search intentionally exposes one accessible row rather than every image.
    /// Its leading print has a fixed 68×100 point slot at the default text size.
    private func searchCover(in row: UIImage) -> UIImage? {
        let rect = CGRect(x: 0, y: max(0, (row.size.height - 100) / 2), width: 68, height: 100)
            .applying(CGAffineTransform(scaleX: row.scale, y: row.scale))
        guard let image = row.cgImage?.cropping(to: rect) else { return nil }
        return UIImage(cgImage: image, scale: row.scale, orientation: .up)
    }

    /// Measure rendered pixels rather than checking an image view's contentMode.
    private func marker(in image: UIImage) -> Marker? {
        guard let cgImage = image.cgImage, image.size.width > 0 else { return nil }
        let width = 180
        let height = max(1, Int((Double(width) * Double(image.size.height) / Double(image.size.width)).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        guard rendered else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1, colored = 0
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
                if max(red, max(green, blue)) - min(red, min(green, blue)) > 80 { colored += 1 }
                if red > 190, green > 150, blue < 80 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX - minX >= 8, maxY - minY >= 8 else { return nil }
        return Marker(bounds: CGRect(x: CGFloat(minX), y: CGFloat(minY),
                                     width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1)),
                      coloredFraction: Double(colored) / Double(width * height))
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
