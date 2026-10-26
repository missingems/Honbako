import XCTest
import UIKit

/// Real touches against the opt-in, in-memory reader. No source or library data.
final class SumiPageCurlGestureTests: XCTestCase {
    @MainActor
    func testLandscapeLTRCommitAndCancel() throws { try exercise(rightToLeft: false, paired: true) }

    @MainActor
    func testLandscapeRTLCommitAndCancel() throws { try exercise(rightToLeft: true, paired: true) }

    @MainActor
    func testShortLandscapeLTRTurn() throws { try exercise(rightToLeft: false, paired: true, shortTurn: true) }

    @MainActor
    func testShortLandscapeRTLTurn() throws { try exercise(rightToLeft: true, paired: true, shortTurn: true) }

    @MainActor
    func testSinglePageCommitAndCancel() throws { try exercise(rightToLeft: false, paired: false) }

    @MainActor
    func testSinglePageRTLCommitAndCancel() throws { try exercise(rightToLeft: true, paired: false) }

    @MainActor
    private func exercise(rightToLeft: Bool, paired: Bool, shortTurn: Bool = false) throws {
        continueAfterFailure = true
        let previousOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = paired ? .landscapeLeft : .portrait
        defer { XCUIDevice.shared.orientation = previousOrientation }
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.launchArguments = ["--sumi-curl-check"] + (rightToLeft ? ["--sumi-curl-rtl"] : [])
        app.launch()
        defer { app.terminate() }
        let initialTitle = paired ? "Pages 1–2" : "Page 1"
        let candidates = app.windows.allElementsBoundByIndex.filter {
            $0.isHittable && !$0.frame.isEmpty && ($0.frame.width > $0.frame.height) == paired
        }
        guard let surface = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            throw XCTSkip("Run this case with the Duo \(paired ? "open" : "closed"); both display poses are covered separately.")
        }
        XCTAssertTrue(app.navigationBars[initialTitle].waitForExistence(timeout: 12), app.debugDescription)
        let rendererID = paired ? "sumi.reader.curl" : "sumi.reader.slide"
        let renderer = surface.descendants(matching: .any).matching(identifier: rendererID).firstMatch
        guard renderer.waitForExistence(timeout: 4) else {
            XCTFail("The actual page renderer was not accessible: \(app.debugDescription)")
            return
        }
        let otherRendererID = paired ? "sumi.reader.slide" : "sumi.reader.curl"
        XCTAssertFalse(surface.descendants(matching: .any).matching(identifier: otherRendererID).firstMatch.exists,
                       "Only landscape pages use the custom curl renderer")
        // Manga advances right to left in both orientations and source orders;
        // portrait uses a native horizontal swipe instead of a paper curl.
        let startX: CGFloat = 0.92
        let endX: CGFloat = shortTurn ? 0.73 : 0.08
        let partialX: CGFloat = 0.89
        // Safe margins can move the paper away from the physical display edge.
        // Exercise the actual renderer instead of swiping the camera margin.
        let start = renderer.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.62))
        let partial = renderer.coordinate(withNormalizedOffset: CGVector(dx: partialX, dy: 0.62))
        start.press(forDuration: 0.08, thenDragTo: partial, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(app.navigationBars[initialTitle].waitForExistence(timeout: 3), "Canceled turn advanced progress")
        let first = XCTAttachment(screenshot: surface.screenshot())
        first.name = "Canceled turn preserves the initial page"
        first.lifetime = .keepAlways
        add(first)
        let end = renderer.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: 0.62))
        start.press(forDuration: 0.08, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
        let nextTitle = paired ? "Pages 3–4" : "Page 2"
        XCTAssertTrue(app.navigationBars[nextTitle].waitForExistence(timeout: 4), "Completed turn did not advance to \(nextTitle): \(app.debugDescription)")
        let next = XCTAttachment(screenshot: surface.screenshot())
        next.name = paired ? "Completed individual leaf" : "Completed native portrait swipe"
        next.lifetime = .keepAlways
        add(next)
        if !paired {
            // A backward swipe can cancel without losing the current page,
            // then slide the actual previous page back into view on completion.
            let backStart = renderer.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.62))
            let backPartial = renderer.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.62))
            backStart.press(forDuration: 0.08, thenDragTo: backPartial,
                            withVelocity: .slow, thenHoldForDuration: 0.5)
            XCTAssertTrue(app.navigationBars[nextTitle].waitForExistence(timeout: 3))
            let backEnd = renderer.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.62))
            backStart.press(forDuration: 0.08, thenDragTo: backEnd,
                            withVelocity: .slow, thenHoldForDuration: 0.05)
            XCTAssertTrue(app.navigationBars[initialTitle].waitForExistence(timeout: 4))
            // A flick also advances from the left half. A slow drag shorter
            // than half a page intentionally returns under native paging.
            let leftStart = renderer.coordinate(withNormalizedOffset: CGVector(dx: 0.40, dy: 0.62))
            leftStart.press(forDuration: 0.08, thenDragTo: end,
                           withVelocity: .fast, thenHoldForDuration: 0)
            XCTAssertTrue(app.navigationBars[nextTitle].waitForExistence(timeout: 4))
        }
        // A native toolbar action uses the same adapter completion contract.
        app.buttons["Previous"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars[initialTitle].waitForExistence(timeout: 4))
        app.terminate()
    }
}
