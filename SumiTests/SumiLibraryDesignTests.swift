@testable import Sumi
import AidokuRunner
import SwiftUI
import UIKit
import XCTest

@MainActor
final class SumiLibraryDesignTests: XCTestCase {
    func testCompactWideAndAccessibleLibraryLayouts() async throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let books = [book("First Light"), book("Rain at the Bookshop"),
            book("The Lantern Map", finished: date), book("A Letter Home", finished: date.addingTimeInterval(60))]
        let shelves = SumiLibraryShelves(books: books)
        for (name, size, scheme, type) in [
            ("compact-light", CGSize(width: 420, height: 1000), ColorScheme.light, DynamicTypeSize.large),
            ("compact-dark", CGSize(width: 420, height: 1000), ColorScheme.dark, DynamicTypeSize.large),
            ("wide-dark", CGSize(width: 1000, height: 700), ColorScheme.dark, DynamicTypeSize.large),
            ("accessible-dark", CGSize(width: 420, height: 1200), ColorScheme.dark, DynamicTypeSize.accessibility3)
        ] {
            let count = type.isAccessibilitySize ? 2 : max(2, Int(size.width / 150))
            let content = ScrollView {
                HonbakoLibraryShelvesView(shelves: shelves,
                    columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: count),
                    hideFinished: false, openingBookID: nil, insertingBookID: nil, openBook: { _, _ in })
            }
            .background(Color(uiColor: .systemBackground))
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, type)
            try await capture(name, size: size, dark: scheme == .dark, content: content)
        }
        try await capture("hidden-finished", size: CGSize(width: 420, height: 800), dark: true,
            content: HonbakoLibraryEmptyView(hasHiddenFinishedBooks: true, showFinished: {}, findBooks: {})
                .environment(\.colorScheme, .dark))
    }

    private func capture<Content: View>(_ name: String, size: CGSize, dark: Bool, content: Content) async throws {
        let host = UIHostingController(rootView: content)
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<8 {
            window.layoutIfNeeded(); host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        XCTAssertEqual(image.size, size)
        let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
        attachment.name = "library-review-\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func book(_ title: String, finished: Date? = nil) -> SumiBook {
        SumiBook(manga: .init(sourceKey: "design-review", key: title, title: title),
            isInLibrary: true, finishedReadingAt: finished)
    }
}
