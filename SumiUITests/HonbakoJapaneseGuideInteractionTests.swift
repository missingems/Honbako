import UIKit
import XCTest

final class HonbakoJapaneseGuideInteractionTests: XCTestCase {
    @MainActor
    func testRomajiIsOnTheMangaAndWordPopupKeepsReadingPosition() throws {
        continueAfterFailure = false
        let originalOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        let app = launch(mode: "rtl")
        defer { app.terminate(); XCUIDevice.shared.orientation = originalOrientation }
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(wait { (reader.value as? String)?.contains("page 4") == true })
        let position = reader.value as? String
        let today = word(containing: "kyou", app)
        XCTAssertTrue(today.waitForExistence(timeout: 40), "The real manga page must expose its recognized word labels: \(reader.debugDescription)")
        XCTAssertTrue(today.isHittable)
        XCTAssertFalse(app.buttons["Honbako.Japanese.Open"].exists)
        XCTAssertFalse(app.buttons["Honbako.JapaneseGuide.Done"].exists)
        let sentence = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Honbako.Reader.Japanese.Word.2."))
        XCTAssertEqual(sentence.count, 5, "The practice sentence must have separate labels for its five words")
        let rows = sentence.allElementsBoundByIndex.map { $0.frame.midY }
        XCTAssertLessThanOrEqual((rows.max() ?? 0) - (rows.min() ?? 0), 1)
        attach(app, "Romaji directly on the manga")
        today.tap()
        let correction = item("Honbako.JapaneseGuide.CorrectText", app)
        XCTAssertTrue(correction.waitForExistence(timeout: 10))
        let source = try XCTUnwrap(correction.value as? String)
        XCTAssertTrue(source.contains("きょうもいっしょによもう"))
        let listen = app.buttons["Honbako.JapaneseGuide.Speak"]
        reveal(listen, app)
        XCTAssertEqual(listen.value as? String, "きょう", "Pronunciation must start with the tapped word")
        attach(app, "A word pronunciation popup over the manga")
        if listen.isEnabled {
            listen.tap()
            let stop = app.buttons["Honbako.JapaneseGuide.StopSpeech"]
            if stop.waitForExistence(timeout: 3) { stop.tap() }
        }
        let whole = app.buttons["Honbako.JapaneseGuide.WholePhrase"]
        let form = item("Honbako.JapaneseGuide.PhraseForm", app)
        for _ in 0..<6 {
            if whole.exists && whole.isHittable { break }
            form.swipeDown()
        }
        XCTAssertTrue(whole.isHittable)
        whole.tap()
        reveal(listen, app)
        XCTAssertEqual(listen.value as? String, source)
        app.buttons["Honbako.JapaneseGuide.PhraseDone"].tap()
        XCTAssertTrue(today.waitForExistence(timeout: 10), "Dismissing the popup must restore the live page labels")
        XCTAssertEqual(reader.value as? String, position)
        XCTAssertFalse(app.buttons["Honbako.Reader.Japanese.Toggle"].exists,
                       "The romaji setting belongs in the menu, without a duplicate toolbar button")
        setRomajiInMenu(false, app)
        XCTAssertTrue(wait { !today.exists }, "The menu setting must hide inline labels after returning to the manga")
        setRomajiInMenu(true, app)
        XCTAssertTrue(today.waitForExistence(timeout: 15))
        // A drag beginning on a label belongs to the reader, not the word popup.
        let readWord = word(containing: "yomou", app)
        XCTAssertTrue(readWord.isHittable)
        let start = readWord.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: -220, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(wait { (reader.value as? String)?.contains("page 5") == true }, "A right-to-left forward drag must still turn the page")
        XCTAssertFalse(correction.exists, "A page drag must not accidentally open a word popup")
        let next = word(containing: "kyou", app)
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(wait { window.frame.width > window.frame.height && next.exists && window.frame.intersects(next.frame) })
        XCTAssertTrue((reader.value as? String)?.contains("page 5") == true)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(wait { window.frame.height > window.frame.width && next.isHittable })
    }

    @MainActor
    func testScrollingReaderShowsWordsAndReturnsFromPopupWithoutMoving() throws {
        continueAfterFailure = false
        let originalOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        let app = launch(mode: "webtoon")
        defer { app.terminate(); XCUIDevice.shared.orientation = originalOrientation }
        let reader = item("Sumi.DirectReader", app)
        let today = word(containing: "kyou", app)
        XCTAssertTrue(today.waitForExistence(timeout: 40), "Scrolling pages must expose the same native inline words: \(reader.debugDescription)")
        XCTAssertTrue(today.isHittable)
        let position = reader.value as? String
        let frame = today.frame
        today.tap()
        let correction = item("Honbako.JapaneseGuide.CorrectText", app)
        XCTAssertTrue(correction.waitForExistence(timeout: 10))
        XCTAssertTrue((correction.value as? String)?.contains("きょうもいっしょによもう") == true)
        app.buttons["Honbako.JapaneseGuide.PhraseDone"].tap()
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        XCTAssertEqual(reader.value as? String, position)
        XCTAssertEqual(today.frame.midY, frame.midY, accuracy: 2, "Studying a word must not scroll the manga")
        let lowerWord = word(containing: "ashita", app)
        XCTAssertTrue(lowerWord.isHittable)
        let lowerFrame = lowerWord.frame
        XCTAssertGreaterThan(lowerFrame.midY, 220, "The test drag must stay within the screen")
        let start = lowerWord.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -180)))
        XCTAssertFalse(correction.exists)
        XCTAssertTrue(wait { !lowerWord.exists || abs(lowerWord.frame.midY - lowerFrame.midY) > 20 },
                      "Vertical drags on labels must scroll the manga; before=\(lowerFrame), after=\(lowerWord.frame), position=\(reader.value ?? "nil")")
    }

    @MainActor
    func testTappingTheMangaKeepsAnnotationsAnchoredWhenChromeChanges() throws {
        continueAfterFailure = false
        let originalOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = originalOrientation }
        for mode in ["rtl", "webtoon"] {
            let app = launch(mode: mode)
            defer { app.terminate() }
            let today = word(containing: "kyou", app)
            XCTAssertTrue(today.waitForExistence(timeout: 40))
            let reader = item("Sumi.DirectReader", app)
            let position = reader.value as? String
            let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Honbako.Reader.Japanese.Word."))
            let frames = Dictionary(grouping: chips.allElementsBoundByIndex, by: \.identifier).mapValues { $0.map(\.frame) }
            XCTAssertGreaterThanOrEqual(frames.count, 5)
            for _ in 0..<4 {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.52)).tap()
                XCTAssertTrue(today.exists)
                XCTAssertEqual(reader.value as? String, position)
                XCTAssertFalse(app.buttons["Honbako.Reader.Japanese.Toggle"].exists)
                for chip in chips.allElementsBoundByIndex {
                    let anchors = try XCTUnwrap(frames[chip.identifier])
                    let current = chip.frame
                    XCTAssertTrue(anchors.contains { abs($0.midX - current.midX) <= 1 && abs($0.midY - current.midY) <= 1 },
                                  "Chrome must not move a word away from its printed anchor")
                }
            }
            attach(app, "Stable inline annotations after repeated page taps in \(mode)")
        }
    }

    @MainActor
    func testChineseChapterCannotStartJapaneseAnnotationsEvenWithRecognizableJapaneseArtwork() {
        continueAfterFailure = false
        let originalOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        let app = launch(mode: "rtl", chineseChapter: true)
        defer { app.terminate(); XCUIDevice.shared.orientation = originalOrientation }
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(wait { (reader.value as? String)?.contains("page 4") == true })
        let words = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Honbako.Reader.Japanese.Word."))
        XCTAssertFalse(words.firstMatch.waitForExistence(timeout: 5),
                       "Explicit Chinese metadata must gate OCR before the real page image arrives")
        let chapters = app.buttons["Sumi.Reader.ChaptersButton"]
        showToolbar(chapters, app)
        chapters.tap()
        XCTAssertFalse(app.switches["Honbako.Reader.Japanese.ToggleInChapters"].exists,
                       "A Chinese chapter must not offer the Japanese-only romaji setting")
        app.buttons["Done"].tap()
        XCTAssertEqual(words.count, 0)
        attach(app, "Chinese edition remains free of Japanese annotations")
    }

    @MainActor
    private func setRomajiInMenu(_ enabled: Bool, _ app: XCUIApplication) {
        let chapters = app.buttons["Sumi.Reader.ChaptersButton"]
        showToolbar(chapters, app)
        chapters.tap()
        let toggle = app.switches["Honbako.Reader.Japanese.ToggleInChapters"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        let expected = enabled ? "1" : "0"
        if toggle.value as? String != expected {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertTrue(wait { toggle.value as? String == expected })
        if enabled { attach(app, "Native green romaji switch in dark menu") }
        app.buttons["Done"].tap()
        XCTAssertTrue(item("Sumi.DirectReader", app).waitForExistence(timeout: 10))
    }

    @MainActor
    private func launch(mode: String, chineseChapter: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check", "--sumi-grid-reading-mode=\(mode)", "--honbako-japanese-guide-check",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-AppleInterfaceStyle", "Dark"]
        if chineseChapter { app.launchArguments.append("--honbako-japanese-guide-chinese-check") }
        app.launch()
        let book = app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-002"]
        XCTAssertTrue(book.waitForExistence(timeout: 20))
        book.tap()
        XCTAssertTrue(item("Sumi.DirectReader", app).waitForExistence(timeout: 20))
        return app
    }

    @MainActor
    private func word(containing text: String, _ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "Honbako.Reader.Japanese.Word.", text)).firstMatch
    }

    @MainActor
    private func showToolbar(_ control: XCUIElement, _ app: XCUIApplication) {
        if control.exists && control.isHittable { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.52)).tap()
        XCTAssertTrue(control.waitForExistence(timeout: 8))
    }

    @MainActor
    private func item(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    private func wait(_ condition: @escaping () -> Bool) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: 10) == .completed
    }

    @MainActor
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        let form = item("Honbako.JapaneseGuide.PhraseForm", app)
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            guard form.exists else { return }
            form.swipeUp()
        }
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
