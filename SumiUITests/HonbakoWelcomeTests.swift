import XCTest

final class HonbakoWelcomeTests: XCTestCase {
    @MainActor
    func testThreeWelcomePagesAndFreeExit() throws {
        let app = launch()
        defer { app.terminate() }
        waitForTitle("Read your own manga", in: app)
        XCTAssertTrue(app.staticTexts["Connect Komga, Kavita, or Suwayomi."].exists)
        attach(app, "Native welcome — your own library")
        let next = assertPinnedNext(in: app, afterScrolling: true)
        next.tap()
        waitForTitle("Your AI reading companion", in: app)
        attach(app, "Native welcome — your AI")
        assertPinnedNext(in: app, afterScrolling: true).tap()
        XCTAssertTrue(app.navigationBars["Plans"].waitForExistence(timeout: 10))
        let free = revealButton("Honbako.Plan.free", in: app)
        XCTAssertTrue(free.isSelected, "Onboarding starts with the free plan selected")
        XCTAssertEqual(free.label, "Free", "The free plan row contains just its plan name")
        let rowWidth = free.frame.width
        let monthly = revealButton("Honbako.Plan.monthly", in: app)
        XCTAssertTrue(monthly.label.contains("Pro per month"))
        XCTAssertEqual(monthly.frame.width, rowWidth, accuracy: 2, "Plans are full-width native rows")
        let annual = revealButton("Honbako.Plan.annual", in: app)
        XCTAssertTrue(annual.label.contains("Pro per year"))
        XCTAssertEqual(annual.frame.width, rowWidth, accuracy: 2, "Annual billing is a row, not a separate card column")
        XCTAssertGreaterThan(annual.frame.minY, monthly.frame.minY)
        let restore = revealButton("Honbako.Plan.Restore", in: app)
        XCTAssertTrue(restore.isHittable, "Restore Purchases must be reachable below the plan choices")
        XCTAssertFalse(next.exists)
        XCTAssertFalse(app.buttons["Honbako.Plan.Subscribe"].exists)
        XCTAssertFalse(app.buttons["Honbako.Plan.ContinueFree"].exists)
        let proceed = app.buttons["Honbako.Plan.Continue"]
        XCTAssertEqual(app.buttons.matching(identifier: "Honbako.Plan.Continue").count, 1)
        XCTAssertTrue(proceed.waitForExistence(timeout: 10))
        XCTAssertTrue(proceed.isHittable, "The single Continue action stays pinned while plans scroll")
        XCTAssertGreaterThanOrEqual(proceed.frame.width, min(contentViewport(in: app).width * 0.8, 400))
        XCTAssertGreaterThanOrEqual(proceed.frame.height, 44)
        XCTAssertLessThan(proceed.frame.height, 70, "Native large button padding must not be compounded")
        attach(app, "Native welcome — compare, choose, continue")
        proceed.tap()
        XCTAssertTrue(app.buttons["Honbako.Library.Settings"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Honbako.Welcome.Title"].exists)
    }

    @MainActor
    func testPreviewCanBeReplayedAfterFreeExitAndNavigatedBack() throws {
        let app = launch()
        waitForTitle("Read your own manga", in: app)
        assertPinnedNext(in: app).tap()
        waitForTitle("Your AI reading companion", in: app)
        assertPinnedNext(in: app).tap()
        XCTAssertTrue(app.navigationBars["Plans"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Honbako.Welcome.Skip"].exists)
        app.buttons["Honbako.Plan.Continue"].tap()
        XCTAssertTrue(app.buttons["Honbako.Library.Settings"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        defer { app.terminate() }
        waitForTitle("Read your own manga", in: app)
        assertPinnedNext(in: app).tap()
        waitForTitle("Your AI reading companion", in: app)
        let sideBack = app.descendants(matching: .any).matching(identifier: "BackButton").firstMatch
        let back = sideBack.exists ? sideBack : app.navigationBars["Your AI"].buttons.element(boundBy: 0)
        XCTAssertTrue(back.isHittable)
        back.tap()
        waitForTitle("Read your own manga", in: app)
    }

    @MainActor
    func testCurrentStepSurvivesOrientationChanges() throws {
        let app = launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        waitForTitle("Read your own manga", in: app)
        XCTAssertFalse(app.buttons["Honbako.Welcome.Step.1"].exists, "Onboarding has no sidebar at any width")
        app.buttons["Honbako.Welcome.Next"].tap()
        waitForTitle("Your AI reading companion", in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForTitle("Your AI reading companion", in: app)
        attach(app, "Native welcome — selected step retained after rotation")
        XCTAssertFalse(app.buttons["Honbako.Welcome.Step.2"].exists, "Rotation must retain the single navigation stack")
        app.buttons["Honbako.Welcome.Next"].tap()
        XCTAssertTrue(app.navigationBars["Plans"].waitForExistence(timeout: 10))
        let monthly = revealMonthlyChoice(in: app)
        monthly.tap()
        assertBilling("Monthly", in: app)
        attach(app, "Native welcome — monthly billing selected")
        XCUIDevice.shared.orientation = .portrait
        _ = revealMonthlyChoice(in: app)
        assertBilling("Monthly", in: app)
        attach(app, "Native welcome — monthly choice retained after rotation")
    }

    @MainActor
    @discardableResult
    private func assertPinnedNext(in app: XCUIApplication, afterScrolling: Bool = false,
                                  file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertFalse(app.buttons["Honbako.Welcome.Skip"].exists, "The intro has no close or Skip button", file: file, line: line)
        let next = app.buttons["Honbako.Welcome.Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), file: file, line: line)
        if afterScrolling {
            XCTAssertTrue(scrollNativeContent(in: app), "The intro must expose a usable scrolling viewport", file: file, line: line)
        }
        XCTAssertTrue(next.isHittable, "Next stays pinned while intro content scrolls", file: file, line: line)
        XCTAssertGreaterThanOrEqual(next.frame.width, min(contentViewport(in: app).width * 0.8, 400), file: file, line: line)
        XCTAssertGreaterThanOrEqual(next.frame.height, 44, file: file, line: line)
        return next
    }

    @MainActor
    private func waitForTitle(_ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let title = app.staticTexts.matching(identifier: "Honbako.Welcome.Title")
            .matching(NSPredicate(format: "label == %@", expected)).firstMatch
        guard title.waitForExistence(timeout: 10) else {
            attach(app, "Missing native welcome destination — \(expected)")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Native welcome accessibility hierarchy after failed navigation"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            XCTFail("Expected the native navigation destination titled \(expected)", file: file, line: line)
            return
        }
    }

    @MainActor
    private func revealMonthlyChoice(in app: XCUIApplication) -> XCUIElement {
        revealButton("Honbako.Plan.monthly", in: app)
    }

    @MainActor
    private func revealButton(_ identifier: String, labelPrefix: String? = nil, in app: XCUIApplication) -> XCUIElement {
        let identified = app.buttons.matching(identifier: identifier).firstMatch
        let labelled = labelPrefix.map { app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", $0)).firstMatch }
        for _ in 0..<12 {
            if identified.exists, identified.isHittable { return identified }
            if let labelled, labelled.exists, labelled.isHittable { return labelled }
            guard scrollNativeContent(in: app) else { break }
        }
        attachFailure(app, name: "Native form button unavailable — \(identifier)")
        XCTFail("The native form must expose \(identifier) after bounded scrolling")
        return identified
    }

    @MainActor
    private func nativeForm(in app: XCUIApplication) -> XCUIElement? {
        let lists = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
        let window = app.windows.firstMatch.frame
        return lists.filter {
            guard $0.exists else { return false }
            let frame = $0.frame
            let visible = frame.intersection(window)
            // Static-only native Lists need not expose a hittable container;
            // their visible content still receives scrolling gestures.
            return frame.width >= 44 && visible.width >= frame.width * 0.8 && visible.height >= 44
        }.max { $0.frame.width < $1.frame.width }
    }

    @MainActor
    private func contentViewport(in app: XCUIApplication) -> CGRect {
        let window = app.windows.firstMatch.frame
        var viewport = (nativeForm(in: app)?.frame ?? window).intersection(window)
        for bar in app.navigationBars.allElementsBoundByIndex where bar.exists && bar.isHittable {
            let frame = bar.frame
            guard frame.intersection(viewport).width > 1 else { continue }
            if frame.width > frame.height {
                let top = max(viewport.minY, frame.maxY)
                viewport = CGRect(x: viewport.minX, y: top, width: viewport.width, height: max(0, viewport.maxY - top))
            } else if frame.height > frame.width, frame.intersection(viewport).height > 1 {
                if frame.midX > viewport.midX {
                    viewport.size.width = max(0, min(viewport.maxX, frame.minX) - viewport.minX)
                } else {
                    let right = viewport.maxX
                    viewport.origin.x = max(viewport.minX, frame.maxX)
                    viewport.size.width = max(0, right - viewport.minX)
                }
            }
        }
        let cellWidths = app.cells.allElementsBoundByIndex.filter {
            $0.exists && $0.frame.intersection(viewport).height > 1
        }.map { $0.frame.width }
        if let contentWidth = cellWidths.max(), contentWidth >= 44 {
            viewport.size.width = min(viewport.width, contentWidth)
        }
        return viewport
    }

    @MainActor
    private func scrollNativeContent(in app: XCUIApplication) -> Bool {
        guard nativeForm(in: app) != nil else { return false }
        var viewport = contentViewport(in: app)
        var bottom = viewport.maxY
        for (identifier, clearance) in [("Honbako.Plan.Continue", 12.0), ("Honbako.Welcome.Next", 12.0)] {
            let button = app.buttons[identifier]
            if button.exists, button.isHittable { bottom = min(bottom, button.frame.minY - clearance) }
        }
        viewport.origin.y += 8
        viewport.size.height = max(0, bottom - viewport.minY)
        guard viewport.width >= 44, viewport.height >= 44 else { return false }
        let window = app.windows.firstMatch
        let origin = window.coordinate(withNormalizedOffset: .zero)
        let x = viewport.midX - window.frame.minX
        let start = origin.withOffset(CGVector(dx: x, dy: viewport.minY + viewport.height * 0.74 - window.frame.minY))
        let end = origin.withOffset(CGVector(dx: x, dy: viewport.minY + viewport.height * 0.4 - window.frame.minY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
        return true
    }

    @MainActor
    private func assertBilling(_ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let selected = app.buttons.matching(identifier: "Honbako.Plan.\(expected.lowercased())").firstMatch
        let value = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            selected.exists && selected.isSelected && selected.value as? String == "Selected"
        }, object: nil)
        let result = XCTWaiter.wait(for: [value], timeout: 10)
        if result != .completed { attachFailure(app, name: "Native billing selection mismatch") }
        XCTAssertEqual(result, .completed,
            "The same billing selection must survive native layout changes", file: file, line: line)
    }

    @MainActor
    private func attachFailure(_ app: XCUIApplication, name: String) {
        attach(app, name)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + " — accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    @MainActor
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check", "--sumi-onboarding-check", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        return app
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
