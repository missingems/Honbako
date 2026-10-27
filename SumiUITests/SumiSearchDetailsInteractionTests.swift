import XCTest
import UIKit
import Vision

final class SumiSearchDetailsInteractionTests: XCTestCase {
    @MainActor
    func testSearchShowsAuthorReleaseAndShortPositionThenResumes() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check"]
        app.launch()
        defer { app.terminate() }
        let grid = item("Sumi.Grid", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        grid.swipeDown()
        let field = item("Sumi.Search.Field", app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        attach(app, "Search rows with title-aligned dividers")
        field.typeText("002")
        let result = app.buttons["Sumi.Search.Book.sumi-grid-preview:book-002"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue((result.value as? String)?.contains("Chapter 2-4") == true)
        XCTAssertFalse((result.value as? String)?.contains("of 8") == true)
        XCTAssertTrue((result.value as? String)?.contains("Generated fixture") == true)
        XCTAssertTrue((result.value as? String)?.contains("Released 2020") == true)
        XCTAssertTrue((result.value as? String)?.contains("Ongoing") == true)
        XCTAssertFalse((result.value as? String)?.contains("Test iPad") == true)
        XCTAssertFalse(app.staticTexts["Resume from Test iPad"].exists)
        let resume = app.buttons["Sumi.Search.Resume.sumi-grid-preview:book-002"]
        XCTAssertTrue(resume.exists)
        XCTAssertTrue(resume.label.hasPrefix("Resume"))
        XCTAssertLessThan(resume.frame.width, 100, "The visible action uses a compact pill")
        XCTAssertFalse(app.buttons["Sumi.Search.Add.sumi-grid-preview:book-002"].exists)
        try assertVisibleReadingDetails(app)
        attach(app, "Search author, release year, RESUME, and chapter/page without totals")
        resume.tap()
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "Chapter 2, page 4"), reader))
    }

    @MainActor
    func testGetAddsWithoutOpeningThenReadOpensTheManga() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check"]
        app.launch()
        defer { app.terminate() }
        let grid = item("Sumi.Grid", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        grid.swipeDown()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        item("Sumi.Search.Field", app).typeText("003")
        let get = app.buttons["Sumi.Search.Add.sumi-grid-preview:book-003"]
        XCTAssertTrue(get.waitForExistence(timeout: 5))
        let result = app.buttons["Sumi.Search.Book.sumi-grid-preview:book-003"]
        XCTAssertTrue((result.value as? String)?.contains("Finished") == true)
        XCTAssertTrue(get.label.hasPrefix("Add"))
        XCTAssertLessThan(get.frame.width, 100)
        _ = try visibleText(in: app, expected: ["ADD", "FINISHED", "GENERATEDFIXTURE"])
        XCTAssertEqual(get.frame.midY, result.frame.midY, accuracy: 1)
        get.tap()
        let searchField = item("Sumi.Search.Field", app)
        XCTAssertTrue(wait(NSPredicate { _, _ in !searchField.isHittable }, grid),
                      "Adding a manga reveals its library destination")
        let savedCover = app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-003"]
        XCTAssertTrue(savedCover.waitForExistence(timeout: 5))
        XCTAssertTrue(savedCover.isHittable, "The transferred cover lands in its real library slot")
        XCTAssertFalse(item("Sumi.DirectReader", app).exists, "Add saves the manga without opening it")
        attach(app, "Added search cover lands in the library")
        for _ in 0..<4 {
            if item("Sumi.Search.Field", app).isHittable { break }
            grid.swipeDown()
        }
        let read = app.buttons["Sumi.Search.Read.sumi-grid-preview:book-003"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        XCTAssertTrue(read.label.hasPrefix("Read"))
        XCTAssertFalse(item("Sumi.DirectReader", app).exists, "Add keeps the manga without opening it")
        attach(app, "Reopening Search shows Read for the saved manga")
        read.tap()
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "Chapter 1, page 1"), reader))
    }

    @MainActor
    func testConnectionEntryUsesManualSetupAndNoRecommendedCatalog() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check"]
        app.launch()
        defer { app.terminate() }
        let grid = item("Sumi.Grid", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        grid.swipeDown()
        let connections = app.buttons["Sumi.Search.Sources"]
        XCTAssertTrue(connections.waitForExistence(timeout: 5))
        XCTAssertEqual(connections.label, "Settings")
        connections.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let hideFinished = app.switches["Honbako.Settings.HideFinishedBooks"]
        let coverDisplay = app.switches["Honbako.Settings.ShowMangaCover"]
        XCTAssertTrue(hideFinished.waitForExistence(timeout: 5))
        XCTAssertTrue(coverDisplay.exists)
        let initial = hideFinished.value as? String
        hideFinished.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in hideFinished.value as? String != initial }, object: hideFinished)], timeout: 3) == .completed)
        hideFinished.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in hideFinished.value as? String == initial }, object: hideFinished)], timeout: 3) == .completed)
        attach(app, "Blue settings controls and optional finished-book filter")
        app.buttons["Getting Started"].tap()
        XCTAssertTrue(app.navigationBars["Getting Started"].waitForExistence(timeout: 5))
        attach(app, "Setup guide lives in Settings")
        item("BackButton", app).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        attach(app, "Settings shows files, personal servers, and manual source setup")
        let sourceLists = app.buttons["Source Lists"]
        for _ in 0..<3 where !sourceLists.exists {
            let anchor = app.buttons["Personal Server"]
            if anchor.exists { anchor.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(sourceLists.waitForExistence(timeout: 5))
        sourceLists.tap()
        XCTAssertTrue(app.navigationBars["Source Lists"].waitForExistence(timeout: 5))
        let add = app.buttons.matching(NSPredicate(format: "label == %@", "Add Source List")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(item("Sumi.Sources.ListURL", app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add"].isEnabled)
        attach(app, "Manual source list URL entry")
    }

    @MainActor private func item(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    @MainActor private func assertVisibleReadingDetails(_ app: XCUIApplication) throws {
        let textBounds = try visibleText(in: app,
            expected: ["CHAPTER2-4", "GENERATEDFIXTURE", "2020", "ONGOING", "RESUME"])
        let position = try XCTUnwrap(textBounds.first { $0.0.contains("CHAPTER2-4") }?.1)
        let action = try XCTUnwrap(textBounds.first { $0.0 == "RESUME" }?.1)
        XCTAssertEqual(position.midX, action.midX, accuracy: 0.025,
                       "The compact chapter-page caption stays beneath Resume")
        XCTAssertLessThan(position.maxY, action.minY)
        XCTAssertLessThan(action.minY - position.maxY, 0.025,
                          "The chapter caption sits close beneath Resume")
        let result = app.buttons["Sumi.Search.Book.sumi-grid-preview:book-002"]
        let resume = app.buttons["Sumi.Search.Resume.sumi-grid-preview:book-002"]
        XCTAssertEqual(resume.frame.midY, result.frame.midY, accuracy: 1,
                       "The full Resume and chapter stack is centered in the row")
    }

    @MainActor private func visibleText(in app: XCUIApplication, expected: [String]) throws -> [(String, CGRect)] {
        let window = try XCTUnwrap(app.windows.allElementsBoundByIndex.first { $0.isHittable })
        var recognized: [String] = []
        var textBounds: [(String, CGRect)] = []
        // Cold Vision initialization can exceed an expectation's timer even
        // when its first completed capture already contains every label.
        for _ in 0..<3 {
            let shot = window.screenshot().image
            let upright = UIGraphicsImageRenderer(size: shot.size).image { _ in
                shot.draw(in: CGRect(origin: .zero, size: shot.size))
            }
            let cg = try XCTUnwrap(upright.cgImage)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request])
            textBounds = (request.results ?? []).compactMap { observation in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                let normalized = text.filter { !$0.isWhitespace }.uppercased()
                    .replacingOccurrences(of: "–", with: "-")
                    .replacingOccurrences(of: "—", with: "-")
                    .replacingOccurrences(of: "−", with: "-")
                return (normalized, observation.boundingBox)
            }
            recognized = textBounds.map(\.0)
            if expected.allSatisfy({ target in recognized.contains { $0.contains(target) } }) { break }
        }
        XCTAssertTrue(expected.allSatisfy { target in recognized.contains { $0.contains(target) } },
                       "Reading details must be visible in the rendered result: \(recognized)")
        return textBounds
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        guard let window = app.windows.allElementsBoundByIndex.first(where: { $0.isHittable }) else { return }
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor private func wait(_ predicate: NSPredicate, _ element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 8) == .completed
    }
}
