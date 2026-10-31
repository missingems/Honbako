@testable import Sumi
import SwiftUI
import UIKit
import XCTest

/// Native component captures for the shared search surface and system form colours.
@MainActor
final class HonbakoSearchSettingsDesignTests: XCTestCase {
    func testGlassSearchAndSystemSettingsInBothAppearances() async throws {
        let books = try HonbakoGuideBook.allCases.map {
            SumiBook(manga: try HonbakoGuideLibrary.makeManga($0), isInLibrary: true)
        }
        await SumiCoverArtworkLoader.shared.prepare(books)
        for dark in [false, true] {
            let search = SumiSearchPresentation()
            search.reveal()
            search.suspendKeyboard()
            let main = SumiMainView(store: SumiLibraryStore(), opening: SumiGridOpeningState(),
                search: search, insertion: SumiLibraryInsertionState(), previewBooks: books,
                openBook: { _, _ in }, dismissSearch: { search.dismiss() }, didAddBook: { _, _ in })
            try await capture("glass-search-\(dark ? "dark" : "light")", dark: dark, content: main)
            try await capture("system-settings-\(dark ? "dark" : "light")", dark: dark,
                content: NavigationStack { SumiPersonalLibrariesView() })
        }
    }

    private func capture<Content: View>(_ name: String, dark: Bool, content: Content) async throws {
        let bounds = CGRect(x: 0, y: 0, width: 420, height: 900)
        let host = UIHostingController(rootView: content.environment(\.colorScheme, dark ? .dark : .light))
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        let window = UIWindow(frame: bounds)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<8 {
            window.layoutIfNeeded()
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        let image = UIGraphicsImageRenderer(bounds: bounds).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
