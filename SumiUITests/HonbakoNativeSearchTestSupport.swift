import XCTest

extension XCUIApplication {
    @MainActor
    var honbakoSearchField: XCUIElement {
        descendants(matching: .any).matching(identifier: "Sumi.Search.Field").firstMatch
    }

    @MainActor
    var honbakoSearchEntry: XCUIElement {
        let floatingButton = buttons["Honbako.Library.Search"]
        if floatingButton.exists { return floatingButton }
        return descendants(matching: .any).matching(identifier: "Honbako.Library.SearchEntry").firstMatch
    }

    @MainActor
    func openHonbakoSearch() throws {
        let entry = honbakoSearchEntry
        guard entry.waitForExistence(timeout: 5) else {
            XCTFail("The library search button must appear")
            throw NSError(domain: "HonbakoUITest", code: 1)
        }
        entry.tap()
        XCTAssertTrue(honbakoSearchField.waitForExistence(timeout: 5), "Search opens the glass results list")
        XCTAssertTrue(keyboards.firstMatch.waitForExistence(timeout: 5), "The glass list owns keyboard focus")
    }

    @MainActor
    func closeHonbakoSearch() {
        let cancel = buttons["Honbako.Library.CloseSearch"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), debugDescription)
        cancel.tap()
    }
}
