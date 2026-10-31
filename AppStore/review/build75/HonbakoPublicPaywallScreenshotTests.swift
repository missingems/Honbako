// Native public paywall captures using real local StoreKit products; no purchase is made.
import Foundation
import StoreKitTest
import UIKit
import XCTest

final class HonbakoPublicPaywallScreenshotTests: XCTestCase {
    @MainActor
    func testPublicMonthlyAndAnnualPaywallScreenshots() async throws {
        continueAfterFailure = false
        let originalOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.missingems.honbaku")
        app.terminate()
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "HonbakoPro", withExtension: "storekit"))
        try validateConfiguration(at: source)
        // Keep the existing, proven StoreKit configuration unchanged. Product.products
        // belongs in the application context; this UI runner verifies the actual app UI.
        let session = try SKTestSession(contentsOf: source)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.timeRate = .realTime
        session.storefront = "USA"
        session.locale = Locale(identifier: "en_US")
        session.clearTransactions()
        defer {
            app.terminate()
            session.clearTransactions()
            XCUIDevice.shared.orientation = originalOrientation
        }
        XCTAssertTrue(session.allTransactions().isEmpty)
        app.launchArguments = ["--sumi-grid-check", "--sumi-onboarding-check", "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US", "-AppleInterfaceStyle", "Dark", "-General.icloudSync", "NO"]
        app.launch()
        let next = app.buttons["Honbako.Welcome.Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        next.tap()
        let aiTitle = app.staticTexts.matching(identifier: "Honbako.Welcome.Title")
            .matching(NSPredicate(format: "label == %@", "Your AI reading companion")).firstMatch
        XCTAssertTrue(aiTitle.waitForExistence(timeout: 10))
        next.tap()
        XCTAssertTrue(app.navigationBars["Plans"].waitForExistence(timeout: 10))
        _ = reveal("Honbako.Plan.annual", app: app)
        try waitForActualAppPrices(app)
        // SwiftUI combines each native button's children into its accessible label.
        // Read the rendered offer there rather than assuming child Text elements
        // remain separate accessibility elements on every iOS version.
        let trialsReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.buttons["Honbako.Plan.monthly"].label.contains("1-week free trial")
                && app.buttons["Honbako.Plan.annual"].label.contains("1-month free trial")
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [trialsReady], timeout: 15), .completed,
                       "Only actual eligible StoreKit introductory offers may appear in these captures")
        XCTAssertTrue(app.buttons["Honbako.Plan.monthly"].label.contains("$2.99"))
        XCTAssertTrue(app.buttons["Honbako.Plan.annual"].label.contains("$28.49"))
        XCTAssertTrue(app.buttons["Honbako.Plan.annual"].label.contains("Save 20%"))
        for (plan, price, period, renewalUnit) in [("monthly", "2.99", "1 week", "per month"), ("annual", "28.49", "1 month", "per year")] {
            let choice = reveal("Honbako.Plan.\(plan)", app: app)
            XCTAssertTrue(choice.isEnabled)
            choice.tap()
            let renewal = app.staticTexts["Honbako.Plan.RenewalPrice"]
            XCTAssertTrue(renewal.waitForExistence(timeout: 10))
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                renewal.label.contains(price) && renewal.label.contains(period)
                    && renewal.label.contains(renewalUnit) && choice.isSelected
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            _ = reveal("Honbako.Plan.Restore", app: app)
            XCTAssertTrue(app.buttons["Honbako.Plan.Continue"].isHittable)
            XCTAssertTrue(visible(app.buttons["Honbako.Plan.monthly"], app: app))
            XCTAssertTrue(visible(app.buttons["Honbako.Plan.annual"], app: app))
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "Public paywall — \(plan) selected — native StoreKit prices and trial"
            capture.lifetime = .keepAlways
            add(capture)
        }
        XCTAssertTrue(session.allTransactions().isEmpty, "Screenshot capture never purchases or creates an entitlement")
    }

    private func validateConfiguration(at url: URL) throws {
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let settings = try XCTUnwrap(config["settings"] as? [String: Any])
        XCTAssertEqual(settings["_locale"] as? String, "en_US")
        XCTAssertEqual(settings["_storefront"] as? String, "USA")
        let groups = try XCTUnwrap(config["subscriptionGroups"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 1)
        let subscriptions = try XCTUnwrap(groups.first?["subscriptions"] as? [[String: Any]])
        let monthly = try XCTUnwrap(subscriptions.first { $0["productID"] as? String == "com.missingems.honbaku.pro" })
        let annual = try XCTUnwrap(subscriptions.first { $0["productID"] as? String == "com.missingems.honbaku.pro.annual" })
        XCTAssertEqual(monthly["recurringSubscriptionPeriod"] as? String, "P1M")
        XCTAssertEqual(annual["recurringSubscriptionPeriod"] as? String, "P1Y")
        let monthlyPrice = try XCTUnwrap((monthly["displayPrice"] as? String).flatMap { Decimal(string: $0) })
        let annualPrice = try XCTUnwrap((annual["displayPrice"] as? String).flatMap { Decimal(string: $0) })
        XCTAssertEqual(monthlyPrice, Decimal(string: "2.99"))
        XCTAssertEqual(annualPrice, Decimal(string: "28.49"))
        XCTAssertLessThanOrEqual(annualPrice, monthlyPrice * 12 * Decimal(string: "0.8")!)
        for (product, period) in [(monthly, "P1W"), (annual, "P1M")] {
            let offer = try XCTUnwrap(product["introductoryOffer"] as? [String: Any])
            XCTAssertEqual(offer["displayPrice"] as? String, "0.00")
            XCTAssertEqual(offer["paymentMode"] as? String, "free")
            XCTAssertEqual(offer["numberOfPeriods"] as? Int, 1)
            XCTAssertEqual(offer["subscriptionPeriod"] as? String, period)
        }
    }

    @MainActor
    private func waitForActualAppPrices(_ app: XCUIApplication) throws {
        let ready = NSPredicate { _, _ in
            app.buttons["Honbako.Plan.monthly"].label.contains("$2.99")
                && app.buttons["Honbako.Plan.annual"].label.contains("$28.49")
        }
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)], timeout: 15) == .completed { return }
        // If StoreKit was not ready at first appearance, use the same visible retry
        // a reader can use. No product data or entitlement is injected into the app.
        let monthly = reveal("Honbako.Plan.monthly", app: app)
        if monthly.isEnabled { monthly.tap() }
        let retry = app.buttons["Try Again"].firstMatch
        for _ in 0..<6 {
            if visible(retry, app: app) { retry.tap(); break }
            scrollForm(app)
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)], timeout: 15)
        if result != .completed {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Public paywall actual product availability"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(result, .completed, "The actual app must fetch and display both StoreKit prices before screenshots")
    }

    @MainActor
    private func reveal(_ id: String, app: XCUIApplication) -> XCUIElement {
        let item = app.buttons[id]
        for _ in 0..<16 {
            if visible(item, app: app) { return item }
            let aboveViewport = item.exists && item.frame.maxY < app.windows.firstMatch.frame.midY
            scrollForm(app, towardTop: aboveViewport)
        }
        XCTFail("The native form must expose \(id) after bounded scrolling")
        return item
    }

    @MainActor
    private func scrollForm(_ app: XCUIApplication, towardTop: Bool = false) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.48 : 0.72))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.72 : 0.48))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    @MainActor
    private func visible(_ item: XCUIElement, app: XCUIApplication) -> Bool {
        item.exists && item.isHittable && item.frame.intersection(app.windows.firstMatch.frame).height >= min(item.frame.height, 44)
    }
}
