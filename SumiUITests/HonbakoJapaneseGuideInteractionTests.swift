import StoreKit
import StoreKitTest
import UIKit
import XCTest

final class HonbakoJapaneseGuideInteractionTests: XCTestCase {
    private var storeKitSession: SKTestSession?

    override func tearDownWithError() throws {
        storeKitSession?.clearTransactions()
        storeKitSession = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testRomajiIsOnTheMangaAndWordPopupKeepsReadingPosition() async throws {
        continueAfterFailure = false
        let originalOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        let app = try await launch(mode: "rtl")
        defer { app.terminate(); XCUIDevice.shared.orientation = originalOrientation }
        let reader = item("Sumi.DirectReader", app)
        XCTAssertTrue(wait { (reader.value as? String)?.contains("page 4") == true })
        let position = reader.value as? String
        let today = word(containing: "kyo", app)
        XCTAssertTrue(today.waitForExistence(timeout: 40), "The real manga page must expose its recognized word labels: \(reader.debugDescription)")
        XCTAssertTrue(today.isHittable)
        XCTAssertFalse(app.buttons["Honbako.Japanese.Open"].exists)
        XCTAssertFalse(app.buttons["Honbako.JapaneseGuide.Done"].exists)
        let sentence = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Honbako.Reader.Japanese.Word.2."))
        XCTAssertEqual(sentence.count, 10, "The practice sentence must have separate character/mora readings, with combined kana kept together")
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
        let readWord = word(containing: "よ, yo", app)
        XCTAssertTrue(readWord.isHittable)
        let start = readWord.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: -220, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(wait { (reader.value as? String)?.contains("page 5") == true }, "A right-to-left forward drag must still turn the page")
        XCTAssertFalse(correction.exists, "A page drag must not accidentally open a word popup")
        let next = word(containing: "kyo", app)
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(wait { window.frame.width > window.frame.height && next.exists && window.frame.intersects(next.frame) })
        XCTAssertTrue((reader.value as? String)?.contains("page 5") == true)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(wait { window.frame.height > window.frame.width && next.isHittable })
    }

    @MainActor
    func testScrollingReaderShowsWordsAndReturnsFromPopupWithoutMoving() async throws {
        continueAfterFailure = false
        let originalOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        let app = try await launch(mode: "webtoon")
        defer { app.terminate(); XCUIDevice.shared.orientation = originalOrientation }
        let reader = item("Sumi.DirectReader", app)
        let today = try visibleWord(containing: "きょ, kyo", app)
        XCTAssertTrue(today.isHittable, "Study a character on a visible page, not a preloaded matching page")
        let position = reader.value as? String
        let frame = today.frame
        today.tap()
        let correction = item("Honbako.JapaneseGuide.CorrectText", app)
        XCTAssertTrue(correction.waitForExistence(timeout: 10))
        XCTAssertTrue((correction.value as? String)?.contains("きょうもいっしょによもう") == true)
        app.buttons["Honbako.JapaneseGuide.PhraseDone"].tap()
        let returned = try visibleWord(containing: "きょ, kyo", app)
        XCTAssertEqual(reader.value as? String, position)
        XCTAssertEqual(returned.frame.midY, frame.midY, accuracy: 2, "Studying a word must not scroll the manga")
        let lowerWord = try visibleWord(containing: "あ, a", app, minimumY: 220)
        XCTAssertTrue(lowerWord.isHittable)
        let lowerFrame = lowerWord.frame
        XCTAssertGreaterThan(lowerFrame.midY, 220, "The test drag must stay within the screen")
        let beforeDrag = try XCTUnwrap(readingPosition(reader.value as? String))
        let start = lowerWord.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -180)))
        XCTAssertFalse(correction.exists, "Dragging a character must not open its study popup")
        // Every fixture page intentionally repeats the same artwork and glyph
        // IDs. Recycling can put a different page's matching character at the
        // exact old screen position; the reader's real progress is authoritative.
        XCTAssertTrue(wait {
            guard let after = self.readingPosition(reader.value as? String) else { return false }
            return after.chapter == beforeDrag.chapter && after.page > beforeDrag.page
        }, "A drag beginning on a character must advance within the same chapter; before=\(beforeDrag), after=\(reader.value ?? "nil")")
        XCTAssertFalse(correction.exists, "The scroll must finish without accidentally opening a study popup")
    }

    @MainActor
    func testTappingTheMangaKeepsAnnotationsAnchoredWhenChromeChanges() async throws {
        continueAfterFailure = false
        let originalOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = originalOrientation }
        for mode in ["rtl", "webtoon"] {
            let app = try await launch(mode: mode)
            defer { app.terminate() }
            let today = word(containing: "kyo", app)
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
    func testChineseChapterCannotStartJapaneseAnnotationsEvenWithRecognizableJapaneseArtwork() async throws {
        continueAfterFailure = false
        let originalOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        let app = try await launch(mode: "rtl", chineseChapter: true)
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
    func testJapaneseGuideStartsOffAndFreeEnableShowsProWithoutLeavingTheBook() async throws {
        continueAfterFailure = false
        let app = try await launch(mode: "rtl", enableGuide: false)
        defer { app.terminate() }
        let reader = item("Sumi.DirectReader", app)
        let position = reader.value as? String
        XCTAssertFalse(app.navigationBars["Honbako Pro"].exists, "Opening an eligible manga never opens a paywall")
        let words = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Honbako.Reader.Japanese.Word."))
        XCTAssertFalse(words.firstMatch.waitForExistence(timeout: 3), "The guide starts off until the reader opts in")
        let chapters = app.buttons["Sumi.Reader.ChaptersButton"]
        showToolbar(chapters, app)
        chapters.tap()
        let toggle = app.switches["Honbako.Reader.Japanese.ToggleInChapters"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "0")
        tapRomajiToggle(toggle, app)
        let proBar = app.navigationBars["Honbako Pro"]
        XCTAssertTrue(proBar.waitForExistence(timeout: 8), "A free user's explicit attempt opens the existing Pro sheet")
        attach(app, "Japanese guide requires Pro only after an explicit enable attempt")
        proBar.buttons["Done"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0", "Declining Pro leaves the guide off")
        app.buttons["Done"].tap()
        XCTAssertEqual(reader.value as? String, position)
        XCTAssertFalse(words.firstMatch.exists)
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
            tapRomajiToggle(toggle, app)
        }
        XCTAssertTrue(wait { toggle.value as? String == expected })
        if enabled { attach(app, "Native green romaji switch in dark menu") }
        app.buttons["Done"].tap()
        XCTAssertTrue(item("Sumi.DirectReader", app).waitForExistence(timeout: 10))
    }

    @MainActor
    private func launch(mode: String, chineseChapter: Bool = false, enableGuide: Bool = true) async throws -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.terminate()
        try await prepareStoreKit(hasPro: enableGuide && !chineseChapter)
        app.launchArguments = ["--sumi-grid-check", "--sumi-grid-reading-mode=\(mode)", "--honbako-japanese-guide-check",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-AppleInterfaceStyle", "Dark"]
        if chineseChapter { app.launchArguments.append("--honbako-japanese-guide-chinese-check") }
        app.launch()
        let book = app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-002"]
        XCTAssertTrue(book.waitForExistence(timeout: 20))
        book.tap()
        XCTAssertTrue(item("Sumi.DirectReader", app).waitForExistence(timeout: 20))
        if enableGuide, !chineseChapter {
            let chapters = app.buttons["Sumi.Reader.ChaptersButton"]
            showToolbar(chapters, app)
            chapters.tap()
            let toggle = app.switches["Honbako.Reader.Japanese.ToggleInChapters"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 10))
            if toggle.value as? String != "1" {
                tapRomajiToggle(toggle, app)
            }
            XCTAssertTrue(wait { toggle.value as? String == "1" || app.navigationBars["Honbako Pro"].exists },
                          "The genuine StoreKit-test purchase must finish restoring before enabling romaji")
            XCTAssertFalse(app.navigationBars["Honbako Pro"].exists,
                           "Paid rendering tests must pass through the real verified StoreKit entitlement; a paywall is a failure")
            XCTAssertEqual(toggle.value as? String, "1")
            app.buttons["Done"].tap()
        }
        return app
    }

    @MainActor
    private func prepareStoreKit(hasPro: Bool) async throws {
        storeKitSession?.clearTransactions()
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "HonbakoPro", withExtension: "storekit"),
                                "Japanese UI tests must bundle their local StoreKit configuration")
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.timeRate = .realTime
        session.clearTransactions()
        storeKitSession = session
        XCTAssertTrue(session.allTransactions().isEmpty, "Each free or paid case begins without an inherited subscription")
        if hasPro {
            let transaction = try await session.buyProduct(identifier: "com.missingems.honbaku.pro")
            XCTAssertEqual(transaction.environment, .xcode, "Only a no-charge local StoreKit transaction may set up paid UI tests")
            XCTAssertEqual(transaction.productID, "com.missingems.honbaku.pro")
            XCTAssertNotNil(transaction.expirationDate)
            await transaction.finish()
            try session.disableAutoRenewForTransaction(identifier: UInt(transaction.id))
        }
        // The application launches normally and verifies Transaction.currentEntitlements.
        // Do not pass the unit-test flag that suppresses its normal store listener.
    }

    @MainActor
    private func tapRomajiToggle(_ toggle: XCUIElement, _ app: XCUIApplication) {
        // A List accessibility node can report hittable while clipped beneath
        // the navigation bar. Validate the entire switch's visible vertical
        // extent against the real sheet viewport before sending any tap.
        let list = item("Sumi.Reader.Chapters", app)
        for _ in 0..<8 {
            let viewport = chapterContentViewport(list, app)
            if switchIsVisible(toggle, in: viewport) { break }
            guard list.exists, viewport.height > 80 else { break }
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: viewport.midX, dy: viewport.midY))
            let end = start.withOffset(CGVector(dx: 0, dy: min(240, viewport.height * 0.35)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        let viewport = chapterContentViewport(list, app)
        attachToggleState("Before romaji tap", toggle: toggle, viewport: viewport, app: app)
        guard switchIsVisible(toggle, in: viewport), toggle.isEnabled else {
            XCTFail("Romaji switch must be fully visible below navigation chrome before tapping: \(toggle.debugDescription)")
            return
        }
        // SwiftUI exposes a full-width parent Switch containing its label and
        // a second native Switch. The parent's center is empty row space; use
        // the actual control bounds exposed by the accessibility hierarchy.
        let nativeSwitch = toggle.switches.firstMatch
        guard switchIsVisible(nativeSwitch, in: viewport), nativeSwitch.isEnabled else {
            XCTFail("The visible Romaji row must expose its native switch control: \(toggle.debugDescription)")
            return
        }
        print("HonbakoJapaneseToggle native control frame=\(nativeSwitch.frame)")
        nativeSwitch.tap()
        attachToggleState("After romaji tap", toggle: toggle, viewport: viewport, app: app)
    }

    @MainActor
    private func chapterContentViewport(_ list: XCUIElement, _ app: XCUIApplication) -> CGRect {
        let window = app.windows.element(boundBy: 0).frame
        let listFrame = list.exists ? list.frame.intersection(window) : window
        let navigation = app.navigationBars["Chapters"]
        var top = listFrame.minY + 8
        if navigation.exists {
            let frame = navigation.frame
            if frame.width > frame.height { top = max(top, frame.maxY + 8) }
        }
        return CGRect(x: listFrame.minX, y: top, width: listFrame.width,
                      height: max(0, listFrame.maxY - top - 16))
    }

    @MainActor
    private func switchIsVisible(_ toggle: XCUIElement, in viewport: CGRect) -> Bool {
        guard toggle.exists, toggle.isHittable else { return false }
        let frame = toggle.frame
        return !frame.isEmpty && viewport.contains(CGPoint(x: frame.midX, y: frame.midY))
            && frame.minY >= viewport.minY && frame.maxY <= viewport.maxY
    }

    @MainActor
    private func attachToggleState(_ name: String, toggle: XCUIElement, viewport: CGRect, app: XCUIApplication) {
        let switchState = toggle.exists
            ? "frame=\(toggle.frame), value=\(String(describing: toggle.value)), hittable=\(toggle.isHittable), enabled=\(toggle.isEnabled)"
            : "not present in the current accessibility hierarchy"
        let summary = "\(name): viewport=\(viewport), switch=\(switchState)"
        print("HonbakoJapaneseToggle " + summary)
        let hierarchy = XCTAttachment(string: summary + "\n" + app.debugDescription)
        hierarchy.name = name + " — hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        attach(app, name)
    }

    private func readingPosition(_ value: String?) -> (chapter: String, page: Int)? {
        guard let value, let separator = value.range(of: ", page ", options: .backwards),
              let page = Int(value[separator.upperBound...]) else { return nil }
        return (String(value[..<separator.lowerBound]), page)
    }

    @MainActor
    private func visibleWord(containing text: String, _ app: XCUIApplication, minimumY: CGFloat = 0) throws -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
            "Honbako.Reader.Japanese.Word.", text))
        var selected: XCUIElement?
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let viewport = app.windows.element(boundBy: 0).frame
            selected = matches.allElementsBoundByIndex.first { candidate in
                let frame = candidate.frame
                return !frame.isEmpty && frame.midY >= minimumY && viewport.contains(frame) && candidate.isHittable
            }
            return selected != nil
        }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 40)
        if result != .completed {
            attach(app, "Visible Japanese character not found")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Visible Japanese character — hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(result, .completed, "A genuinely visible character label must be available for study and scrolling")
        return try XCTUnwrap(selected)
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
