@testable import Sumi
import SwiftUI
import StoreKitTest
import UIKit
import Vision
import XCTest

@MainActor
final class HonbakoWelcomeDesignTests: XCTestCase {
    func testCompactRegularAndAccessibleWelcomePresentations() async throws {
        // Only the dedicated StoreKit test scheme loads local App Store products.
        // This exercises real Product formatting/purchase APIs without inventing UI prices.
        let session: SKTestSession?
        if ProcessInfo.processInfo.arguments.contains("--honbako-storekit-tests") {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "HonbakoPro", withExtension: "storekit"))
            session = try SKTestSession(contentsOf: url)
            session?.resetToDefaultState()
            session?.disableDialogs = true
            session?.clearTransactions()
            await HonbakoProStore.shared.refreshEntitlement()
            await HonbakoProStore.shared.loadProduct()
        } else { session = nil }
        defer { session?.clearTransactions() }
        for (name, size, scheme, type, sizeClass, page) in [
            ("closed-light", CGSize(width: 420, height: 760), ColorScheme.light, DynamicTypeSize.large, UserInterfaceSizeClass.compact, HonbakoWelcomePage.library),
            ("closed-dark-ai", CGSize(width: 420, height: 760), ColorScheme.dark, DynamicTypeSize.large, UserInterfaceSizeClass.compact, HonbakoWelcomePage.assistant),
            ("open-dark-ai", CGSize(width: 1000, height: 740), ColorScheme.dark, DynamicTypeSize.large, UserInterfaceSizeClass.regular, HonbakoWelcomePage.assistant),
            ("accessible-dark", CGSize(width: 420, height: 900), ColorScheme.dark, DynamicTypeSize.accessibility3, UserInterfaceSizeClass.compact, HonbakoWelcomePage.library),
            ("plans-accessible-dark", CGSize(width: 420, height: 900), ColorScheme.dark, DynamicTypeSize.accessibility3, UserInterfaceSizeClass.compact, HonbakoWelcomePage.plans),
            ("plans-iphone-dark", CGSize(width: 390, height: 844), ColorScheme.dark, DynamicTypeSize.large, UserInterfaceSizeClass.compact, HonbakoWelcomePage.plans),
            ("plans-dark", CGSize(width: 1000, height: 740), ColorScheme.dark, DynamicTypeSize.large, UserInterfaceSizeClass.regular, HonbakoWelcomePage.plans)
        ] {
            let content = HonbakoWelcomeView(onFinish: {}, startingAt: page)
                .environment(\.colorScheme, scheme)
                .environment(\.dynamicTypeSize, type)
                .environment(\.horizontalSizeClass, sizeClass)
            try await capture(name, size: size, dark: scheme == .dark, page: page, content: content)
        }
        if session != nil {
            XCTAssertNotNil(HonbakoProStore.shared.annualProduct)
            XCTAssertEqual(HonbakoProStore.shared.introductoryTrials[HonbakoProStore.productID]?.periodUnit, .week)
            XCTAssertEqual(HonbakoProStore.shared.introductoryTrials[HonbakoProStore.annualProductID]?.periodUnit, .month)
            let paid = HonbakoProView(feature: .remoteMCP)
                .environment(\.colorScheme, .dark)
            try await capture("plans-annual-disclosure", size: CGSize(width: 390, height: 844), dark: true,
                              page: .plans, requiresRenewalPrice: true, content: paid)
        }
    }

    func testSubscribersSeeManagementAndFreeUsersSeeOffers() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "HonbakoPro", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        let store = HonbakoProStore.shared
        await store.refreshEntitlement()
        await store.loadProduct()
        defer {
            session.clearTransactions()
            Task { await store.refreshEntitlement() }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(rootView: HonbakoProView(feature: nil).environment(\.colorScheme, .dark))
        host.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        try await renderFrames(window: window, host: host)
        let free = try snapshot(host.view, expectedSize: window.bounds.size)
        let freeText = try recognizedText(free)
        XCTAssertTrue(freeText.contains("compareplans"), "Free members should see what Pro offers")
        attach(free, name: "pro-free-offering")
        let transaction = try await session.buyProduct(identifier: HonbakoProStore.productID)
        await transaction.finish()
        try session.disableAutoRenewForTransaction(identifier: UInt(transaction.id))
        await store.refreshEntitlement()
        XCTAssertTrue(store.hasVerifiedPro)
        try await renderFrames(window: window, host: host)
        let member = try snapshot(host.view, expectedSize: window.bounds.size)
        let memberText = try recognizedText(member)
        XCTAssertTrue(memberText.contains("proisactive") && memberText.contains("managesubscription"))
        XCTAssertFalse(memberText.contains("compareplans") || memberText.contains("chooseplan") || memberText.contains("restorepurchases"),
                       "Existing members get management, with no plan picker or purchase CTA")
        attach(member, name: "pro-member-management")
        let count = session.allTransactions().count
        await store.purchase(plan: .annual)
        XCTAssertEqual(session.allTransactions().count, count, "An active subscriber cannot accidentally buy again")
        try session.refundTransaction(identifier: UInt(transaction.id))
        for _ in 0..<50 {
            await store.refreshEntitlement()
            if !store.hasPro { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(store.hasPro)
        try await renderFrames(window: window, host: host)
        let returned = try snapshot(host.view, expectedSize: window.bounds.size)
        XCTAssertTrue(try recognizedText(returned).contains("compareplans"), "A refunded member can see the Pro offering again")
    }

    func testSettingsPaperInLightAndDark() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        for dark in [false, true] {
            let content = SumiSourcesView().environment(\.colorScheme, dark ? .dark : .light)
            let host = UIHostingController(rootView: content)
            host.overrideUserInterfaceStyle = dark ? .dark : .light
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = host
            window.isHidden = false
            try await renderFrames(window: window, host: host)
            let image = try snapshot(host.view, expectedSize: window.bounds.size)
            attach(image, name: dark ? "settings-paper-dark" : "settings-paper-light")
            let text = try recognizedText(image)
            XCTAssertTrue(text.contains("settings") && text.contains("coverdisplay"),
                          "Settings controls must remain readable on paper: \(text)")
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    private func capture<Content: View>(_ name: String, size: CGSize, dark: Bool,
                                        page: HonbakoWelcomePage, requiresRenewalPrice: Bool = false, content: Content) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }, "Native welcome snapshots require the foreground test-host scene")
        let host = UIHostingController(rootView: content)
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        try await renderFrames(window: window, host: host)
        let image = try snapshot(host.view, expectedSize: size)
        attach(image, name: name)

        // Capture native List/Form contents, not just their navigation chrome.
        // Rendered body text must be present inside the actual screenshot.
        let text = try recognizedText(image)
        if requiresRenewalPrice {
            XCTAssertTrue(text.contains("autorenews") && text.contains("year") && text.contains("monthfree") && text.contains("then"),
                          "The eligible annual trial and subsequent full annual renewal must be visible beside Continue before scrolling: \(text)")
        }
        let expectedTitle: String
        switch page {
        case .library: expectedTitle = "readyourownmanga"
        case .assistant: expectedTitle = "readingcompanion"
        case .plans: expectedTitle = "free"
        }
        XCTAssertTrue(text.contains(expectedTitle), "Missing visible welcome title in \(name): \(text)")
        if page != .plans {
            let detail = page == .library ? "files" : "page"
            XCTAssertTrue(text.contains(detail), "The native list body must render inside the viewport in \(name)")
        } else {
            // Show both ends of the real scrolling paywall. StoreKit prices are
            // left untouched: unavailable products retain the app's honest label.
            var comparisonText = text
            for attempt in 1...3 where !comparisonText.contains("owncollection") {
                let form = try XCTUnwrap(visibleVerticalLists(in: host.view).max { $0.bounds.width < $1.bounds.width })
                let bottom = form.contentSize.height - form.bounds.height + form.adjustedContentInset.bottom
                form.setContentOffset(CGPoint(x: form.contentOffset.x, y: min(bottom, form.contentOffset.y + form.bounds.height * 0.3)), animated: false)
                try await renderFrames(window: window, host: host)
                let rows = try snapshot(host.view, expectedSize: size)
                attach(rows, name: name + "-comparison-rows-\(attempt)")
                comparisonText += try recognizedText(rows)
            }
            XCTAssertTrue(comparisonText.contains("compareplans") && comparisonText.contains("owncollection") && comparisonText.contains("pro"),
                "The actual comparison table must render its Free/Pro headers and collection row: \(comparisonText)")
            var legalVisible = false
            for attempt in 1...3 {
                // Native navigation retains earlier destinations and has its own
                // horizontal wrapper scrollers. Target only the visible native
                // List/Form that can actually scroll vertically.
                let scroll = try XCTUnwrap(visibleVerticalLists(in: host.view).max { $0.bounds.width < $1.bounds.width },
                    "The plans form must expose a visible vertical list")
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x,
                    y: max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
                try await renderFrames(window: window, host: host)
                let bottom = try snapshot(host.view, expectedSize: size)
                let bottomText = try recognizedText(bottom)
                legalVisible = bottomText.contains("privacypolicy")
                attach(bottom, name: name + "-bottom-\(attempt)")
                if legalVisible { break }
            }
            XCTAssertTrue(legalVisible, "The native plans form must scroll to its legal links")
        }
    }

    private func renderFrames<Content: View>(window: UIWindow, host: UIHostingController<Content>) async throws {
        for _ in 0..<8 {
            window.layoutIfNeeded()
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func snapshot(_ view: UIView, expectedSize: CGSize) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = expectedSize.width == 390 ? 3 : 2
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            XCTAssertTrue(view.drawHierarchy(in: view.bounds, afterScreenUpdates: true))
        }
        XCTAssertEqual(image.size, expectedSize)
        return image
    }

    private func recognizedText(_ image: UIImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        let cgImage = try XCTUnwrap(image.cgImage)
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined().lowercased().filter(\.isLetter)
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        guard !view.isHidden, view.alpha > 0 else { return [] }
        var found = view.subviews.flatMap { scrollViews(in: $0) }
        if let scroll = view as? UIScrollView { found.append(scroll) }
        return found
    }

    private func visibleVerticalLists(in root: UIView) -> [UIScrollView] {
        scrollViews(in: root).filter { scroll in
            guard scroll is UICollectionView || scroll is UITableView,
                  scroll.isScrollEnabled, scroll.bounds.width > 0, scroll.bounds.height > 0 else { return false }
            let minimumOffset = -scroll.adjustedContentInset.top
            let maximumOffset = scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
            guard maximumOffset > minimumOffset + 8 else { return false }
            let frame = scroll.convert(scroll.bounds, to: root)
            let visible = frame.intersection(root.bounds)
            return !visible.isNull && visible.width * visible.height >= frame.width * frame.height * 0.8
        }
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = "welcome-\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
