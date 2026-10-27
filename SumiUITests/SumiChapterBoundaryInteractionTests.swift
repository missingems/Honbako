import UIKit
import Vision
import XCTest

final class SumiChapterBoundaryInteractionTests: XCTestCase {
    @MainActor
    func testNextChapterLoadsNewArtworkAndKeepsCloseReachable() throws {
        try exerciseChapterBoundary(paired: true)
    }

    @MainActor
    func testPortraitSwipePastLastPageLoadsNextChapterArtwork() throws {
        try exerciseChapterBoundary(paired: false)
    }

    @MainActor
    private func exerciseChapterBoundary(paired: Bool) throws {
        continueAfterFailure = false
        let previousOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = paired ? .landscapeLeft : .portrait
        defer { XCUIDevice.shared.orientation = previousOrientation }
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check", "--sumi-grid-reading-mode=rtl"]
        app.launch()
        defer { app.terminate() }
        let book = app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-001"]
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        book.tap()
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 20))
        let close = app.buttons["SumiReader.Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        guard let surface = app.windows.allElementsBoundByIndex
            .filter({ $0.isHittable && !$0.frame.isEmpty && ($0.frame.width > $0.frame.height) == paired })
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            throw XCTSkip("Run this chapter boundary case with the Duo \(paired ? "open" : "closed").")
        }
        let scrubber = item("Sumi.Reader.Scrubber", app)
        XCTAssertTrue(scrubber.exists)
        let finalPage = paired ? 7 : 8
        for _ in 0..<5 {
            if reader.value as? String == "Chapter 1, page \(finalPage)" { break }
            if !scrubber.exists || !scrubber.isHittable {
                reader.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.4)).tap()
            }
            XCTAssertTrue(wait(NSPredicate { _, _ in scrubber.exists && scrubber.isHittable }, scrubber))
            let previousPage = reader.value as? String
            if scrubber.frame.height > scrubber.frame.width { scrubber.swipeUp() }
            else { scrubber.swipeLeft() }
            XCTAssertTrue(wait(NSPredicate { _, _ in reader.value as? String != previousPage }, reader),
                          "Wait for the selected page to settle before continuing along the larger previews")
        }
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Chapter 1, page \(finalPage)"), reader),
                      "Scrubbing to the end must select the last page or spread: \(reader.value ?? "missing")")

        let pager = item(paired ? "sumi.reader.curl" : "sumi.reader.slide", app)
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        XCTAssertFalse(item(paired ? "sumi.reader.slide" : "sumi.reader.curl", app).exists)
        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.62))
            .press(forDuration: 0.08,
                   thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.24, dy: 0.62)),
                   withVelocity: .slow, thenHoldForDuration: 0.08)
        let end = app.staticTexts["Chapter 1 End"]
        XCTAssertTrue(end.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(app.buttons["Sumi.Reader.ContinueChapter"].exists)
        XCTAssertFalse(app.buttons["Next Chapter"].exists)
        XCTAssertFalse(app.buttons["Previous Chapter"].exists)
        if paired {
            XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Chapter 2, page 1"), reader))
            try verifyArtwork(surface, containing: ["CHAPTER2", "PAGE01"])
            XCTAssertLessThan(end.frame.midX, surface.frame.midX, "Chapter end belongs on the left")
        }
        attach(surface.screenshot(), "Numbered chapter end and adjacent next cover")
        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.62))
            .press(forDuration: 0.08,
                   thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.24, dy: 0.62)),
                   withVelocity: .slow, thenHoldForDuration: 0.08)
        let nextPage = paired ? 2 : 1
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Chapter 2, page \(nextPage)"), reader))
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        try verifyArtwork(surface, containing: ["CHAPTER2", paired ? "PAGE02" : "PAGE01"])
        XCTAssertFalse(end.exists)
        attach(surface.screenshot(), "Next chapter shows its real first page")

        if !paired {
            // A scrub used to rebuild UIKit's stale neighbor queue and conceal
            // this bug. The new chapter must accept consecutive native swipes.
            for page in 2...3 {
                pager.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.62))
                    .press(forDuration: 0.08,
                           thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.24, dy: 0.62)),
                           withVelocity: .slow, thenHoldForDuration: 0.08)
                XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Chapter 2, page \(page)"), reader),
                              "The loaded chapter must swipe forward without scrubbing first")
            }
            try verifyArtwork(surface, containing: ["CHAPTER2", "PAGE03"])
            attach(surface.screenshot(), "New chapter advances by swipe without using scrubber")
        }

        if !close.isHittable {
            reader.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.62)).tap()
        }
        XCTAssertTrue(wait(NSPredicate { _, _ in close.isHittable }, close))
        close.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), reader))
        XCTAssertTrue(book.waitForExistence(timeout: 6))
    }

    @MainActor private func item(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor private func wait(_ predicate: NSPredicate, _ element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10) == .completed
    }

    @MainActor private func verifyArtwork(_ surface: XCUIElement, containing targets: [String]) throws {
        var recognized: [String] = []
        for _ in 0..<3 {
            let screenshot = surface.screenshot().image
            let upright = UIGraphicsImageRenderer(size: screenshot.size).image { _ in
                screenshot.draw(in: CGRect(origin: .zero, size: screenshot.size))
            }
            let image = try XCTUnwrap(upright.cgImage)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
            recognized = (request.results ?? []).filter { $0.boundingBox.height > 0.025 }.compactMap {
                $0.topCandidates(1).first?.string.filter { !$0.isWhitespace }.uppercased()
            }
            if targets.allSatisfy({ target in recognized.contains { $0.contains(target) } }) { break }
        }
        XCTAssertTrue(targets.allSatisfy { target in recognized.contains { $0.contains(target) } },
                       "New chapter artwork is missing; recognized \(recognized)")
    }

    private func attach(_ screenshot: XCUIScreenshot, _ title: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = title
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
