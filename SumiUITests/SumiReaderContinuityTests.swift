import UIKit
import Vision
import XCTest

final class SumiReaderContinuityTests: XCTestCase {
    @MainActor
    func testAscendingSpreadOrderAndRotationKeepVisibleArtworkAndBookmark() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(mode: "rtl")
        defer { app.terminate() }
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["SumiReader.Close"].waitForExistence(timeout: 8))
        let surface = try XCTUnwrap(app.windows.allElementsBoundByIndex.first { $0.isHittable && $0.frame.width > $0.frame.height })
        XCTAssertTrue(item("sumi.reader.curl", app).waitForExistence(timeout: 5))
        XCTAssertFalse(item("sumi.reader.slide", app).exists)
        _ = try artwork(in: surface, containing: ["PAGE01"], side: .left)
        _ = try artwork(in: surface, containing: ["PAGE02"], side: .right)
        item("Sumi.Reader.Spread.3-4", app).tap()
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "page 3"), reader))
        for orientation in [UIDeviceOrientation.portrait, .landscapeRight, .portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let resized = wait(NSPredicate { _, _ in
                app.windows.allElementsBoundByIndex.contains {
                    $0.isHittable && ($0.frame.width > $0.frame.height) == orientation.isLandscape
                }
            }, app)
            guard resized else {
                throw XCTSkip("This Duo runtime did not apply XCUIDevice orientation to its scene. Use Device Hub rotation to verify the actual viewport.")
            }
            let rendererID = orientation.isLandscape ? "sumi.reader.curl" : "sumi.reader.slide"
            let otherRendererID = orientation.isLandscape ? "sumi.reader.slide" : "sumi.reader.curl"
            XCTAssertTrue(item(rendererID, app).waitForExistence(timeout: 8),
                          "Rotation must replace the page renderer for the new orientation")
            XCTAssertFalse(item(otherRendererID, app).exists,
                           "The outgoing renderer must not remain over the visible artwork")
            XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "page 3"), reader))
            let window = try XCTUnwrap(app.windows.allElementsBoundByIndex.first { $0.isHittable && $0.frame.contains(reader.frame.center) })
            _ = try artwork(in: window, containing: ["PAGE03"])
            if orientation == .portrait {
                let close = app.buttons["SumiReader.Close"]
                if !close.isHittable {
                    reader.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.4)).tap()
                }
                let scrub = item("Sumi.Reader.Scrubber", app)
                XCTAssertTrue(wait(NSPredicate { _, _ in scrub.exists && scrub.isHittable }, scrub))
                XCTAssertGreaterThan(scrub.frame.width, scrub.frame.height)
                XCTAssertEqual(scrub.frame.midX, window.frame.midX, accuracy: 8,
                               "The open Duo centers portrait page previews at the bottom")
            }
            attach(window.screenshot(), "Visible page retained after \(orientation.rawValue)")
        }
        let pager = item("sumi.reader.curl", app)
        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.6))
            .press(forDuration: 0.08, thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.6)), withVelocity: .slow, thenHoldForDuration: 0.05)
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "page 5"), reader))
    }

    @MainActor
    func testWebtoonSourceScrollsVerticallyAndSurvivesRotation() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(mode: "webtoon")
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["SumiReader.Close"].waitForExistence(timeout: 8))
        XCTAssertFalse(item("sumi.reader.curl", app).exists)
        XCTAssertFalse(item("sumi.reader.slide", app).exists, "Vertical sources retain continuous scrolling")
        let surface = try XCTUnwrap(app.windows.allElementsBoundByIndex.first { $0.isHittable })
        attach(surface.screenshot(), "Vertical reader before finger scroll")
        // A fit-width page can be several viewports tall on Duo's wide display.
        // Read through it with real drags rather than assuming one viewport is one page.
        for _ in 0..<4 {
            if (reader.value as? String) != "Chapter 1, page 1" { break }
            reader.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.8))
                .press(forDuration: 0.08, thenDragTo: reader.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.15)), withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        let advanced = wait(NSPredicate(format: "value MATCHES %@", "Chapter 1, page [2-8]"), reader)
        attach(surface.screenshot(), "Vertical reader after finger scroll")
        XCTAssertTrue(advanced, app.debugDescription)
        let position = reader.value as? String
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", position ?? ""), reader))
        XCTAssertFalse(item("sumi.reader.curl", app).exists)
        XCTAssertFalse(item("sumi.reader.slide", app).exists)
        let window = try XCTUnwrap(app.windows.allElementsBoundByIndex.first { $0.isHittable && $0.frame.width > $0.frame.height })
        attach(window.screenshot(), "Vertical source retains its page after rotation")
    }

    @MainActor
    func testLanguageSelectionKeepsChapterListInTheChosenTranslation() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(mode: "rtl", extra: ["--sumi-grid-languages"])
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Sumi.Reader.ChaptersButton"].waitForExistence(timeout: 20))
        app.buttons["Sumi.Reader.ChaptersButton"].tap()
        let picker = item("Sumi.Reader.Language", app)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let spanish = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Spanish")).firstMatch
        XCTAssertTrue(spanish.waitForExistence(timeout: 5), app.debugDescription)
        spanish.tap()
        let chapterPanel = item("Sumi.Reader.Chapters", app)
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), chapterPanel),
                      "Selecting a translation continues the equivalent chapter immediately")
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "Chapter 1"), reader))
        app.buttons["Sumi.Reader.ChaptersButton"].tap()
        let translated = app.buttons["Sumi.Reader.Chapter.chapter-2-es"]
        XCTAssertTrue(translated.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Sumi.Reader.Chapter.chapter-2"].exists)
        translated.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "Chapter 2"), reader))
        app.buttons["Sumi.Reader.ChaptersButton"].tap()
        XCTAssertTrue(app.buttons["Sumi.Reader.Chapter.chapter-3-es"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Sumi.Reader.Chapter.chapter-3"].exists)
        attach(app.screenshot(), "Chapters stay in the selected language")
    }

    @MainActor private func launch(mode: String, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check", "--sumi-grid-reading-mode=\(mode)"] + extra
        app.launch()
        let book = app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-001"]
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        book.tap()
        return app
    }

    @MainActor private func item(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor private func wait(_ predicate: NSPredicate, _ element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10) == .completed
    }

    @MainActor private func artwork(in surface: XCUIElement, containing texts: [String], side: UIRectEdge? = nil) throws -> [String: CGRect] {
        var found: [String: CGRect] = [:]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            let shot = surface.screenshot().image
            let upright = UIGraphicsImageRenderer(size: shot.size).image { _ in
                shot.draw(in: CGRect(origin: .zero, size: shot.size))
            }
            guard var image = upright.cgImage else { return false }
            if let side {
                let width = image.width / 2
                guard let crop = image.cropping(to: CGRect(x: side == .left ? 0 : width,
                    y: 0, width: width, height: image.height)) else { return false }
                image = crop
            }
            try? VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
            found = [:]
            for result in request.results ?? [] {
                let text = result.topCandidates(1).first?.string.filter { !$0.isWhitespace }.uppercased() ?? ""
                for target in texts where text.contains(target) {
                    // The actual page lettering is much larger than thumbnail text.
                    if result.boundingBox.height > (found[target]?.height ?? 0) { found[target] = result.boundingBox }
                }
            }
            return texts.allSatisfy { found[$0] != nil }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 12), .completed, "Artwork missing: \(texts), found \(found)")
        return found
    }

    private func attach(_ screenshot: XCUIScreenshot, _ name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
