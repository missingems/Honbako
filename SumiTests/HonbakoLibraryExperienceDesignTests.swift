@testable import Sumi
import SwiftUI
import UIKit
import XCTest

@MainActor
final class HonbakoLibraryExperienceDesignTests: XCTestCase {
    func testNativeLibrarySearchAndCenteredCloseCaptures() async throws {
        let guides = try HonbakoGuideBook.allCases.map { SumiBook(manga: try HonbakoGuideLibrary.makeManga($0), isInLibrary: true) }
        let tutorial = SumiBook(manga: try HonbakoTutorialManga.makeManga(), isInLibrary: true)
        let books = [tutorial] + guides
        await SumiCoverArtworkLoader.shared.prepare(books)
        for (name, size, active, large) in [
            ("library-dark", CGSize(width: 420, height: 1000), false, false),
            ("library-wide-dark", CGSize(width: 1000, height: 700), false, false),
            ("library-large-text", CGSize(width: 420, height: 1200), false, true),
            ("native-search", CGSize(width: 420, height: 1000), true, false)
        ] {
            let store = SumiLibraryStore()
            let search = SumiSearchPresentation()
            if active { search.reveal(); search.suspendKeyboard(); search.query = "" }
            let view = SumiMainView(store: store, opening: SumiGridOpeningState(), search: search,
                insertion: SumiLibraryInsertionState(), previewBooks: books, openBook: { _, _ in },
                dismissSearch: { search.dismiss() }, didAddBook: { _, _ in })
                .environment(\.colorScheme, .dark)
                .environment(\.dynamicTypeSize, large ? .accessibility3 : .large)
            try await capture(name, size: size, content: view)
        }
        for language in HonbakoTutorialManga.languages {
            let size = CGSize(width: 768, height: 1152)
            let sheet = UIGraphicsImageRenderer(size: size).image { _ in
                for (row, guide) in HonbakoGuideBook.allCases.enumerated() {
                    for column in 0...HonbakoGuideBook.pageCount {
                        HonbakoGuideRenderer.render(guide: guide, page: column == 0 ? nil : column, language: language)
                            .draw(in: CGRect(x: CGFloat(column) * 153.6, y: CGFloat(row) * 384, width: 153.6, height: 230.4))
                    }
                }
            }
            attach("guide-pages-\(language)", image: sheet)
        }
        let viewport = CGRect(x: 0, y: 0, width: 420, height: 700)
        let spread = UIGraphicsImageRenderer(size: viewport.size).image { _ in
            for (guide, rect) in zip(HonbakoGuideBook.allCases.prefix(2),
                [CGRect(x: 0, y: 0, width: 210, height: 700), CGRect(x: 210, y: 0, width: 210, height: 700)]) {
                HonbakoGuideRenderer.render(guide: guide, page: 1, language: "en").draw(in: rect)
            }
        }
        let cover = HonbakoGuideRenderer.render(guide: .find, page: nil, language: "en")
        let stage = try SumiBookStageView(frame: viewport, cover: cover, spread: spread, paired: true, centeredClose: true)
        let host = UIViewController(); host.view.backgroundColor = .black; host.view.addSubview(stage)
        let window = UIWindow(frame: viewport); window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        for (name, progress) in [("open", CGFloat(1)), ("folding", 0.65), ("centered", 0.32), ("returned", 0)] {
            XCTAssertTrue(stage.draw(progress: progress, source: CGRect(x: 20, y: 450, width: 100, height: 150), deltaTime: 1 / 60))
            CATransaction.flush()
            try await Task.sleep(for: .milliseconds(80))
            let image = UIGraphicsImageRenderer(bounds: viewport).image { _ in
                XCTAssertTrue(host.view.drawHierarchy(in: viewport, afterScreenUpdates: true))
            }
            attach("center-close-\(name)", image: image)
        }
    }

    private func capture<Content: View>(_ name: String, size: CGSize, content: Content) async throws {
        let host = UIHostingController(rootView: content)
        host.overrideUserInterfaceStyle = .dark
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<12 {
            window.layoutIfNeeded(); host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        XCTAssertEqual(image.size, size)
        attach(name, image: image)
    }

    private func attach(_ name: String, image: UIImage) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name + ".png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
