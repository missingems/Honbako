import ImageIO
import UIKit
import Vision
import XCTest

final class SumiGridInteractionTests: XCTestCase {
    @MainActor
    func testLibrarySectionHeaderStaysPinnedWhileBooksScroll() throws {
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--honbako-catalog-check"]
        app.launch()
        defer { app.terminate() }
        let grid = element("Sumi.Grid", app)
        let header = element("Honbako.Library.Header.Popular", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        let original = header.frame
        grid.swipeUp()
        XCTAssertTrue(header.exists)
        XCTAssertEqual(header.frame.minY, original.minY, accuracy: 1,
                       "The library section title stays pinned while the manga move beneath it")
        attach(app.screenshot(), "Pinned library header with space above its label")
    }

    @MainActor
    func testDirectCloseReturnsToTheOriginalOffCenterSlot() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch()
        defer { app.terminate() }
        let grid = element("Sumi.Grid", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        let target = book(6, app)
        XCTAssertTrue(target.exists)
        let original = target.frame
        target.tap()
        let reader = element("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        let close = app.buttons["SumiReader.Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let surface = try activeSurface(app, content: reader)
        assertScrubberPlacement(app, surface: surface,
            scrubber: element("Sumi.Reader.Scrubber", app), badge: element("Sumi.Reader.PagePosition", app))
        close.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), reader, timeout: 8))
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertEqual(target.frame.minX, original.minX, accuracy: 1)
        XCTAssertEqual(target.frame.minY, original.minY, accuracy: 1)
        XCTAssertEqual(target.frame.width, original.width, accuracy: 1)
        XCTAssertEqual(target.frame.height, original.height, accuracy: 1)
        attach(grid.screenshot(), "Direct close restores the original off-center book slot")
    }

    @MainActor
    func testLeadingEdgeBackCanCancelThenCloseAndPreserveTheSelectedPage() throws {
        let app = launch()
        defer { app.terminate() }
        let grid = element("Sumi.Grid", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        let surface = try activeSurface(app, content: grid)
        book(1, app).tap()
        let reader = element("Sumi.DirectReader", app)
        guard app.buttons["SumiReader.Close"].waitForExistence(timeout: 15) else { XCTFail("Book did not open"); return }
        let value = reader.value as? String
        let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.52))
        start.press(forDuration: 0.08, thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.24, dy: 0.52)), withVelocity: .slow, thenHoldForDuration: 0.4)
        XCTAssertTrue(app.buttons["SumiReader.Close"].waitForExistence(timeout: 5))
        XCTAssertEqual(reader.value as? String, value, "Canceling back must retain the exact reader page")
        attach(surface.screenshot(), "Canceled binder back swipe returns to the same spread")
        let paired = surface.frame.width > surface.frame.height
        let selected = paired ? 3 : 2
        let thumbnail = element(paired ? "Sumi.Reader.Spread.3-4" : "Sumi.Reader.Thumbnail.2", app)
        guard thumbnail.waitForExistence(timeout: 5) else { XCTFail("Next preview missing"); return }
        thumbnail.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "page \(selected)"), reader, timeout: 6))
        start.press(forDuration: 0.08, thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.52)), withVelocity: .slow, thenHoldForDuration: 0.2)
        guard wait(NSPredicate(format: "exists == false"), reader, timeout: 8) else {
            attach(surface.screenshot(), "Binder back swipe failure"); XCTFail("Leading edge swipe did not close the book"); return
        }
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        book(1, app).tap()
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "Chapter 1, page \(selected)"), reader, timeout: 15))
        attach(surface.screenshot(), "Swipe back and reopen preserves the selected source page")
        try close(app, surface)
    }

    @MainActor
    func testLandscapeSpreadScrubbingAndResume() throws {
        let previous = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = previous }
        try testDistinctThumbnailImagesChaptersScrubbingAndExactResume()
    }

    @MainActor
    func testProgressiveSearchPullCanRetreatThenCommitAndReopen() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch()
        defer { app.terminate() }
        let grid = element("Sumi.Grid", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        let surface = try activeSurface(app, content: grid)
        let original = book(1, app).frame
        let field = element("Sumi.Search.Field", app)
        XCTAssertFalse(field.isHittable)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let start = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        XCTContext.runActivity(named: "Partial Spotlight pull held before release") { _ in
            start.press(forDuration: 0.08,
                        thenDragTo: start.withOffset(CGVector(dx: 0, dy: 56)),
                        withVelocity: XCUIGestureVelocity(rawValue: 32), thenHoldForDuration: 6)
        }
        XCTAssertFalse(field.isHittable, "A partial pull must retreat without opening search")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Previewing search must not bring up the keyboard")
        XCTAssertEqual(book(1, app).frame.minY, original.minY, accuracy: 1)
        grid.swipeDown()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("042")
        XCTAssertTrue(app.buttons["Sumi.Search.Book.sumi-grid-preview:book-042"].waitForExistence(timeout: 5))
        app.buttons["Sumi.Search.Dismiss"].coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.04)).tap()
        XCTAssertTrue(wait(NSPredicate { _, _ in !field.isHittable }, field, timeout: 5))
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), app.keyboards.firstMatch, timeout: 5))
        grid.swipeDown()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "042")
        XCTAssertTrue(app.buttons["Sumi.Search.Book.sumi-grid-preview:book-042"].exists)
        attach(surface.screenshot(), "Reopened Spotlight retains the query and keyboard focus")
    }

    @MainActor
    func testFullScreenLibraryRevealsNativeSearchOnPull() throws {
        let app = launch()
        defer { app.terminate() }
        let grid = element("Sumi.Grid", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        let surface = try activeSurface(app, content: grid)
        XCTAssertFalse(element("Sumi.Search.Field", app).isHittable, "Search stays hidden until a pull")
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertEqual(grid.frame.minX, surface.frame.minX, accuracy: 1)
        XCTAssertEqual(grid.frame.maxX, surface.frame.maxX, accuracy: 1)
        let original = book(1, app).frame
        grid.swipeDown()
        let field = element("Sumi.Search.Field", app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Pulling search focuses its field automatically")
        field.typeText("042")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "Sumi.Search.Book.", "042")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Sumi.Search.Sources"].exists)
        let underlyingBook = book(1, app)
        XCTAssertTrue(!underlyingBook.exists || !underlyingBook.isHittable,
                      "Library stays behind the search overlay and out of accessibility focus")
        attach(surface.screenshot(), "Spotlight overlay with focused native field and concise book results")
        app.buttons["Sumi.Search.Dismiss"].coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.04)).tap()
        XCTAssertTrue(wait(NSPredicate { _, _ in !field.isHittable }, field, timeout: 5))
        XCTAssertTrue(book(1, app).waitForExistence(timeout: 5))
        XCTAssertEqual(book(1, app).frame.minX, original.minX, accuracy: 1)
        XCTAssertEqual(book(1, app).frame.minY, original.minY, accuracy: 1)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }

    @MainActor
    func testFloatingCoverHasLoadingPillAndOpensToSeparateControls() throws {
        let app = launch(["--sumi-loading-delay=6"])
        defer { app.terminate() }
        let grid = element("Sumi.Grid", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        let surface = try activeSurface(app, content: grid)
        book(1, app).tap()
        let loading = element("Sumi.Book.Loading", app)
        XCTAssertTrue(loading.waitForExistence(timeout: 3))
        let cover = element("Sumi.Book.HoverCover", app)
        let pill = element("Sumi.Book.LoadingPill", app)
        XCTAssertTrue(cover.exists && pill.exists)
        XCTAssertTrue(pill.label.contains("Loading"))
        XCTAssertFalse(app.buttons["SumiReader.Close"].exists)
        XCTAssertFalse(element("Sumi.Book.CoverDimming", app).exists)
        XCTAssertFalse(element("Sumi.Book.LoadingMaterial", app).exists)
        XCTAssertFalse(element("Sumi.Book.LoadingVibrancy", app).exists)
        XCTAssertGreaterThanOrEqual(pill.frame.minY, cover.frame.maxY + 8)
        XCTAssertEqual(pill.frame.midX, cover.frame.midX, accuracy: 4)
        attach(surface.screenshot(), "Floating cover with a compact loading pill beneath it")
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), loading, timeout: 20))
        let reader = element("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 5))
        _ = try waitForText("PAGE01", surface)
        XCTAssertTrue(app.buttons["SumiReader.Close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sumi.Reader.ChaptersButton"].exists)
        XCTAssertFalse(app.buttons["Sumi.Reader.FitButton"].exists)
        let scrubber = element("Sumi.Reader.Scrubber", app)
        XCTAssertTrue(scrubber.exists)
        let badge = element("Sumi.Reader.PagePosition", app)
        XCTAssertTrue(badge.exists)
        assertScrubberPlacement(app, surface: surface, scrubber: scrubber, badge: badge)
        XCTAssertFalse(app.navigationBars.allElementsBoundByIndex.contains { $0.isHittable })
        attach(surface.screenshot(), "Reader actions and filmstrip share one dark glass toolbar")
        try close(app, surface)
    }

    @MainActor
    func testOutsideLoadingTapReturnsTheBookToItsOriginalGridSlot() throws {
        let app = launch(["--sumi-loading-delay=6"])
        defer { app.terminate() }
        let grid = element("Sumi.Grid", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        let surface = try activeSurface(app, content: grid)
        let original = book(1, app).frame
        book(1, app).tap()
        let loading = element("Sumi.Book.Loading", app)
        XCTAssertTrue(loading.waitForExistence(timeout: 3))
        let cover = element("Sumi.Book.HoverCover", app)
        XCTAssertTrue(element("Sumi.Book.LoadingPill", app).exists)
        XCTAssertFalse(app.buttons["SumiReader.Close"].exists)
        let point = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.04))
        XCTAssertFalse(cover.frame.contains(CGPoint(x: surface.frame.minX + surface.frame.width * 0.03,
                                                   y: surface.frame.minY + surface.frame.height * 0.04)))
        point.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), loading, timeout: 8))
        XCTAssertFalse(element("Sumi.DirectReader", app).exists)
        XCTAssertTrue(book(1, app).waitForExistence(timeout: 5))
        let returned = book(1, app).frame
        XCTAssertEqual(returned.minX, original.minX, accuracy: 1)
        XCTAssertEqual(returned.minY, original.minY, accuracy: 1)
        XCTAssertEqual(returned.size.width, original.size.width, accuracy: 1)
        XCTAssertEqual(returned.size.height, original.size.height, accuracy: 1)
        attach(surface.screenshot(), "Outside tap lowers the loading book into its original slot")
    }

    @MainActor
    func testLandscapeToolbarFollowsTheTappedPageAndHidesWhenTurning() throws {
        let previous = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = previous }
        let app = launch()
        defer { app.terminate() }
        let grid = element("Sumi.Grid", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        let surface = try activeSurface(app, content: grid)
        book(1, app).tap()
        let reader = element("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["SumiReader.Close"].waitForExistence(timeout: 5))
        guard surface.frame.width > surface.frame.height else {
            throw XCTSkip("Run the landscape toolbar case with the Duo open.")
        }
        let pager = try pageRenderer(app, surface)
        let toolbar = element("Sumi.Reader.Toolbar", app)
        let systemSidebar = toolbar.frame.height > toolbar.frame.width
        if surface.frame.width > 800 {
            XCTAssertFalse(systemSidebar, "The open book canvas keeps its controls at the touched bottom corner")
        }
        let originalToolbarX = toolbar.frame.midX
        let leftTap = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
        leftTap.tap()
        if systemSidebar {
            XCTAssertTrue(wait(NSPredicate { _, _ in !toolbar.isHittable }, toolbar, timeout: 5))
            leftTap.tap()
            XCTAssertTrue(wait(NSPredicate { _, _ in toolbar.isHittable }, toolbar, timeout: 5))
            XCTAssertEqual(toolbar.frame.midX, originalToolbarX, accuracy: 1)
        } else {
            XCTAssertTrue(wait(NSPredicate { _, _ in
                toolbar.isHittable && toolbar.frame.midX < surface.frame.midX
            }, toolbar, timeout: 5))
        }
        assertScrubberPlacement(app, surface: surface,
            scrubber: element("Sumi.Reader.Scrubber", app), badge: element("Sumi.Reader.PagePosition", app))
        attach(surface.screenshot(), "Left-page tap respects the system toolbar placement")
        try tapPage(app, surface)
        if systemSidebar {
            XCTAssertTrue(wait(NSPredicate { _, _ in !toolbar.isHittable }, toolbar, timeout: 5))
            try tapPage(app, surface)
            XCTAssertTrue(wait(NSPredicate { _, _ in toolbar.isHittable }, toolbar, timeout: 5))
            XCTAssertEqual(toolbar.frame.midX, originalToolbarX, accuracy: 1)
        } else {
            XCTAssertTrue(wait(NSPredicate { _, _ in
                toolbar.isHittable && toolbar.frame.midX > surface.frame.midX
            }, toolbar, timeout: 5))
        }
        attach(surface.screenshot(), "Right-page tap respects the system toolbar placement")
        let startX = min(0.9, max(0.6,
            (toolbar.frame.minX - 24 - pager.frame.minX) / pager.frame.width))
        let start = pager.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.62))
        let end = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.62))
        start.press(forDuration: 0.08, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(wait(NSPredicate(format: "value MATCHES %@", "Chapter 1, page [3-8]"), reader, timeout: 6))
        XCTAssertTrue(wait(NSPredicate { _, _ in !toolbar.isHittable }, toolbar, timeout: 5))
        XCTAssertFalse(element("Sumi.Reader.ScrubHandoff", app).exists)
        attach(surface.screenshot(), "Turning the page dismisses the unified toolbar")
        try close(app, surface)
    }

    @MainActor
    func testPortraitSwipeAdvancesCancelsAndReturnsWithRealArtwork() throws {
        let previous = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = previous }
        let app = launch(["--sumi-grid-reading-mode=rtl"])
        defer { app.terminate() }
        let grid = element("Sumi.Grid", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        let surface = try activeSurface(app, content: grid)
        guard surface.frame.width < surface.frame.height else {
            throw XCTSkip("Run the portrait swipe case with the Duo closed.")
        }
        book(1, app).tap()
        let reader = element("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["SumiReader.Close"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForStatusClock(visible: true, in: surface), "Reader controls also reveal the status bar")
        let pager = try pageRenderer(app, surface)
        _ = try waitForText("PAGE01", surface)
        let toolbar = element("Sumi.Reader.Toolbar", app)
        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.45))
            .press(forDuration: 0.08,
                   thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.45)),
                   withVelocity: .slow, thenHoldForDuration: 0.05)
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Chapter 1, page 2"), reader, timeout: 6))
        XCTAssertTrue(wait(NSPredicate { _, _ in !toolbar.isHittable }, toolbar, timeout: 5))
        XCTAssertTrue(waitForStatusClock(visible: false, in: surface))
        _ = try waitForText("PAGE02", surface)
        attach(surface.screenshot(), "Portrait swipe reveals the actual next page and hides controls")

        let backStart = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45))
        backStart.press(forDuration: 0.08,
                        thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.45)),
                        withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Chapter 1, page 2"), reader, timeout: 4))
        _ = try waitForText("PAGE02", surface)
        backStart.press(forDuration: 0.08,
                        thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45)),
                        withVelocity: .slow, thenHoldForDuration: 0.05)
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Chapter 1, page 1"), reader, timeout: 6))
        _ = try waitForText("PAGE01", surface)
        attach(surface.screenshot(), "Backward portrait swipe restores the actual previous page")
        try tapPage(app, surface)
        XCTAssertTrue(wait(NSPredicate { _, _ in toolbar.isHittable }, toolbar, timeout: 5))
        XCTAssertTrue(waitForStatusClock(visible: true, in: surface))
        assertScrubberPlacement(app, surface: surface,
            scrubber: element("Sumi.Reader.Scrubber", app), badge: element("Sumi.Reader.PagePosition", app))
        try close(app, surface)
    }

    @MainActor
    func testDistinctThumbnailImagesChaptersScrubbingAndExactResume() throws {
        let app = launch()
        defer { app.terminate() }
        let grid = element("Sumi.Grid", app)
        XCTAssertTrue(grid.waitForExistence(timeout: 15))
        let surface = try activeSurface(app, content: grid)
        book(1, app).tap()
        let reader = element("Sumi.DirectReader", app)
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["SumiReader.Close"].waitForExistence(timeout: 5))
        let paired = surface.frame.width > surface.frame.height
        let first = element("Sumi.Reader.SelectedSpread", app)
        let second = element(paired ? "Sumi.Reader.Spread.3-4" : "Sumi.Reader.Thumbnail.2", app)
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Preview ready"), first, timeout: 8))
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Preview ready"), second, timeout: 8))
        let image1 = try interior(first.screenshot())
        let image2 = try interior(second.screenshot())
        XCTAssertNotEqual(image1, image2, "Different source pages must display different thumbnail artwork")
        let renderer = try pageRenderer(app, surface)
        XCTAssertEqual(renderer.frame.width, surface.frame.width, accuracy: 1)
        XCTAssertEqual(renderer.frame.height, surface.frame.height, accuracy: 1)
        let before = renderer.frame
        try tapPage(app, surface)
        try tapPage(app, surface)
        XCTAssertEqual(renderer.frame.width, before.width, accuracy: 1)
        XCTAssertEqual(renderer.frame.height, before.height, accuracy: 1)
        let strip = element("Sumi.Reader.ThumbnailStrip", app)
        let verticalStrip = strip.frame.height > strip.frame.width
        if verticalStrip {
            XCTAssertEqual(first.frame.midY, strip.frame.midY, accuracy: 1)
        } else {
            XCTAssertEqual(first.frame.midX, strip.frame.midX, accuracy: 1)
        }
        if paired { XCTAssertEqual(first.label, "Pages 1 and 2") }
        let dragStart = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let dragEnd = strip.coordinate(withNormalizedOffset: verticalStrip
            ? CGVector(dx: 0.5, dy: 0.25)
            : CGVector(dx: 0.25, dy: 0.5))
        dragStart.press(forDuration: 0.08, thenDragTo: dragEnd, withVelocity: .slow, thenHoldForDuration: 0.2)
        let dragged = wait(NSPredicate(format: "value MATCHES %@", "Chapter 1, page [2-8]"), reader, timeout: 6)
        XCTAssertTrue(dragged,
                      "Dragging the actual filmstrip must commit a different canonical page; actual: \(reader.value ?? "nil")")
        guard dragged else {
            attach(surface.screenshot(), "Filmstrip drag failure")
            print("Filmstrip frame:", strip.frame, app.debugDescription)
            return
        }
        XCTAssertFalse(app.buttons["Sumi.Reader.FitButton"].exists)
        try tapPage(app, surface)
        XCTAssertTrue(wait(NSPredicate { _, _ in app.buttons["Sumi.Reader.ChaptersButton"].isHittable }, reader, timeout: 5))
        app.buttons["Sumi.Reader.ChaptersButton"].tap()
        let chapter = element("Sumi.Reader.Chapter.chapter-2", app)
        let chapterList = element("Sumi.Reader.Chapters", app)
        for _ in 0..<3 where !chapter.exists {
            let frame = chapterList.frame
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: frame.midX, dy: frame.maxY - 60))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + 120)))
        }
        XCTAssertTrue(chapter.waitForExistence(timeout: 5), app.debugDescription)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: chapter.frame.midX, dy: chapter.frame.midY)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "Chapter 2"), reader, timeout: 8))
        let chosenPage = paired ? 3 : 2
        let page2 = element(paired ? "Sumi.Reader.Spread.3-4" : "Sumi.Reader.Thumbnail.2", app)
        XCTAssertTrue(page2.waitForExistence(timeout: 5))
        page2.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "page \(chosenPage)"), reader, timeout: 6))
        _ = try waitForText(paired ? "PAGE03" : "PAGE02", surface)
        attach(surface.screenshot(), "Distinct page previews in glass with page position above the selected thumbnail")
        try close(app, surface)
        XCTAssertTrue(grid.waitForExistence(timeout: 6))
        book(1, app).tap()
        XCTAssertTrue(reader.waitForExistence(timeout: 15))
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "Chapter 2, page \(chosenPage)"), reader, timeout: 8))
        try close(app, surface)
    }

    @MainActor private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = true
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-grid-check"] + extra
        app.launch()
        return app
    }
    @MainActor private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    @MainActor private func book(_ number: Int, _ app: XCUIApplication) -> XCUIElement {
        app.buttons["Sumi.Grid.Book.sumi-grid-preview:book-" + String(format: "%03d", number)].firstMatch
    }
    @MainActor private func wait(_ predicate: NSPredicate, _ object: Any, timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: object)], timeout: timeout) == .completed
    }
    @MainActor private func waitForStatusClock(visible: Bool, in surface: XCUIElement) -> Bool {
        // Duo's shared system status area is rendered outside the app's AX
        // subtree. Verify its actual clock pixels instead of app.statusBars.
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let shot = surface.screenshot().image
            let upright = UIGraphicsImageRenderer(size: shot.size).image { _ in
                shot.draw(in: CGRect(origin: .zero, size: shot.size))
            }
            guard let cg = upright.cgImage,
                  let top = cg.cropping(to: CGRect(x: 0, y: 0, width: cg.width, height: cg.height / 3)) else { return false }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: top, orientation: .up).perform([request])
            let clock = (request.results ?? []).contains {
                $0.topCandidates(1).first?.string.range(of: "\\b[0-2]?\\d:[0-5]\\d\\b", options: .regularExpression) != nil
            }
            return clock == visible
        }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 6) == .completed
    }
    @MainActor private func activeSurface(_ app: XCUIApplication, content: XCUIElement) throws -> XCUIElement {
        let frame = content.frame
        return try XCTUnwrap(app.windows.allElementsBoundByIndex.first { $0.isHittable && $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) })
    }
    @MainActor private func assertScrubberPlacement(
        _ app: XCUIApplication, surface: XCUIElement, scrubber: XCUIElement, badge: XCUIElement,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let strip = element("Sumi.Reader.ThumbnailStrip", app)
        XCTAssertTrue(strip.exists, file: file, line: line)
        let toolbar = element("Sumi.Reader.Toolbar", app)
        XCTAssertTrue(toolbar.exists, file: file, line: line)
        let surfaceFrame = surface.frame
        let scrubberFrame = scrubber.frame
        XCTAssertTrue(surfaceFrame.insetBy(dx: -1, dy: -1).contains(toolbar.frame),
                      "The page controls must remain inside the display", file: file, line: line)
        XCTAssertTrue(toolbar.frame.insetBy(dx: -1, dy: -1).contains(scrubberFrame), file: file, line: line)
        let vertical = toolbar.frame.height > toolbar.frame.width
        if vertical {
            XCTAssertGreaterThan(strip.frame.height, strip.frame.width,
                                 "The system side toolbar contains a vertical page strip", file: file, line: line)
        } else {
            XCTAssertGreaterThan(strip.frame.width, strip.frame.height, file: file, line: line)
        }
        let close = app.buttons["SumiReader.Close"]
        let chapters = app.buttons["Sumi.Reader.ChaptersButton"]
        XCTAssertTrue(close.exists && chapters.exists, file: file, line: line)
        XCTAssertFalse(close.frame.intersects(scrubberFrame), file: file, line: line)
        XCTAssertFalse(chapters.frame.intersects(scrubberFrame), file: file, line: line)
        XCTAssertGreaterThanOrEqual(close.frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(chapters.frame.height, 44, file: file, line: line)
        XCTAssertEqual(min(scrubberFrame.width, scrubberFrame.height), 40, accuracy: 1,
                       "The page strip is thinner than the separate navigation buttons", file: file, line: line)
        if vertical {
            let sideClearance = min(toolbar.frame.minX - surfaceFrame.minX, surfaceFrame.maxX - toolbar.frame.maxX)
            XCTAssertGreaterThanOrEqual(sideClearance, 7, file: file, line: line)
            XCTAssertLessThanOrEqual(sideClearance, 24, file: file, line: line)
            XCTAssertTrue(badge.frame.maxX <= scrubberFrame.minX || badge.frame.minX >= scrubberFrame.maxX,
                          "Page position stays beside the side scrubber", file: file, line: line)
            let clock = app.statusBars.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]{1,2}:[0-9]{2}")).firstMatch
            if clock.waitForExistence(timeout: 2) {
                XCTAssertEqual(toolbar.frame.midX, clock.frame.midX, accuracy: 2,
                               "Vertical controls align with the visible status column", file: file, line: line)
            }
            return
        }
        if surfaceFrame.width < surfaceFrame.height {
            let centered = abs(toolbar.frame.midX - surfaceFrame.midX) <= 1
            XCTAssertTrue(centered || toolbar.frame.maxX <= surfaceFrame.midX - 8
                          || toolbar.frame.minX >= surfaceFrame.midX + 8,
                          "Portrait controls center on a single canvas or stay in the touched inner-display half", file: file, line: line)
        }
        XCTAssertLessThanOrEqual(badge.frame.maxY, scrubberFrame.minY, file: file, line: line)
        let bottomClearance = surfaceFrame.maxY - toolbar.frame.maxY
        XCTAssertGreaterThanOrEqual(bottomClearance, 7, file: file, line: line)
        XCTAssertLessThanOrEqual(bottomClearance, 44,
                                "The bottom rail should reserve only the safe inset and its small margin", file: file, line: line)
    }
    @MainActor private func pageRenderer(_ app: XCUIApplication, _ surface: XCUIElement) throws -> XCUIElement {
        let paired = surface.frame.width > surface.frame.height
        let pager = element(paired ? "sumi.reader.curl" : "sumi.reader.slide", app)
        XCTAssertTrue(pager.waitForExistence(timeout: 5), "The renderer must match the current display orientation")
        XCTAssertFalse(element(paired ? "sumi.reader.slide" : "sumi.reader.curl", app).exists)
        return pager
    }
    @MainActor private func tapPage(_ app: XCUIApplication, _ surface: XCUIElement) throws {
        let pager = try pageRenderer(app, surface)
        pager.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.4)).tap()
    }
    @MainActor private func close(_ app: XCUIApplication, _ surface: XCUIElement) throws {
        let button = app.buttons["SumiReader.Close"].firstMatch
        if !button.isHittable { try tapPage(app, surface) }
        XCTAssertTrue(button.waitForExistence(timeout: 4))
        button.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), element("Sumi.DirectReader", app), timeout: 8))
    }
    private func attach(_ shot: XCUIScreenshot, _ name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func interior(_ shot: XCUIScreenshot) throws -> Data {
        let image = try XCTUnwrap(shot.image.cgImage)
        let inset = CGFloat(8) * shot.image.scale
        let rect = CGRect(x: inset, y: inset, width: max(1, CGFloat(image.width) - inset * 2), height: max(1, CGFloat(image.height) - inset * 2))
        return try XCTUnwrap(image.cropping(to: rect)).dataProvider!.data! as Data
    }
    @MainActor private func waitForText(_ text: String, _ surface: XCUIElement) throws -> [String] {
        var last: [String] = []
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            last = (try? recognize(surface.screenshot())) ?? []
            return last.contains { $0.filter { !$0.isWhitespace }.uppercased().contains(text) }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, "Missing \(text) in actual page: \(last)")
        return last
    }
    private func recognize(_ shot: XCUIScreenshot) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        let image = shot.image
        let orientation: CGImagePropertyOrientation
        switch image.imageOrientation {
        case .up: orientation = .up
        case .upMirrored: orientation = .upMirrored
        case .down: orientation = .down
        case .downMirrored: orientation = .downMirrored
        case .left: orientation = .left
        case .leftMirrored: orientation = .leftMirrored
        case .right: orientation = .right
        case .rightMirrored: orientation = .rightMirrored
        @unknown default: orientation = .up
        }
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage), orientation: orientation).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}
