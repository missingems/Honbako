@testable import Sumi
import AidokuRunner
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class SumiReaderChromeDesignTests: XCTestCase {
    func testNativeTitlesStayReadableOverArtworkAfterThemeUpdates() async throws {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var values = original
        values["General.incognitoMode"] = true
        values["Reader.liveText"] = false
        defaults.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }

        for style in [UIUserInterfaceStyle.light, .dark] {
            let reader = ReaderViewController(source: nil,
                manga: AidokuRunner.Manga(sourceKey: "chrome-render-test", key: "book", title: "Reader Contrast"),
                chapter: .init(key: "seven", chapterNumber: 7), startPage: 1)
            reader.sumiIsPreparingOpening = true
            let container = SumiDirectReaderController(content: reader)
            let fixture = try makeWindow(root: container, style: style)
            defer {
                reader.sumiIsPreparingOpening = true
                fixture.close()
            }
            reader.loadViewIfNeeded()
            let artwork = ChromeArtworkView(frame: reader.view.bounds)
            artwork.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            reader.view.addSubview(artwork)
            // Let UIKit finish the hidden staging appearance, then perform
            // the same opening commit as the real book transition. Merely
            // clearing the staging flag leaves viewDidAppear free to hide bars.
            await settle(fixture.window)
            reader.sumiDidOpenPreparedBook()
            reader.showBars()

            for (index, backdrop) in ChromeArtworkView.Backdrop.allCases.enumerated() {
                artwork.backdrop = backdrop
                reader.chapter = .init(key: "chapter-\(index)", chapterNumber: Float(7 + index))
                reader.loadNavbarTitle()
                // Reader changes call this again after the initial setup. A
                // default/transparent appearance must never replace image chrome.
                reader.updateTextThemeOverride()
                await settle(fixture.window)
                XCTAssertFalse(container.isNavigationBarHidden, "A committed book must display its native navigation bar")
                XCTAssertFalse(container.navigationBar.isHidden)
                XCTAssertEqual(container.navigationBar.alpha, 1, accuracy: 0.001)
                XCTAssertGreaterThan(container.navigationBar.bounds.width, 0)
                XCTAssertGreaterThan(container.navigationBar.bounds.height, 0)
                XCTAssertNil(reader.navigationItem.titleView, "The rendered title must remain UIKit's native title")
                XCTAssertEqual(reader.navigationItem.title, "Reader Contrast")
                try assertReadableAppearances(reader.navigationItem, traits: fixture.window.traitCollection)
                let image = try snapshot(fixture.window)
                attach(image, name: "reader-native-\(name(style))-\(backdrop.rawValue)")
                let text = try recognizedText(image)
                XCTAssertTrue(text.contains("readercontrast"), "The native manga title must render over \(backdrop): \(text)")
                XCTAssertTrue(text.contains("chapter\(7 + index)"), "The native chapter subtitle must render over \(backdrop): \(text)")
            }
        }
    }

    func testGlassTintDoesNotFadeReaderContentsAndLibraryButtons() async throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let root = UIViewController()
            let fixture = try makeWindow(root: root, style: style)
            defer { fixture.close() }
            let artwork = ChromeArtworkView(frame: root.view.bounds)
            artwork.backdrop = .checkerboard
            artwork.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            root.view.addSubview(artwork)

            let toolbar = SumiReaderToolbar(frame: CGRect(x: 24, y: 260, width: 342, height: 48))
            let scrubber = SumiPageScrubber()
            let page = practiceThumbnail()
            scrubber.imageProvider = { _ in page }
            toolbar.mount(scrubber)
            root.view.addSubview(toolbar)
            scrubber.update(chapterKey: "chrome-test", totalPages: 6, currentPage: 3)
            toolbar.setVisible(true, animated: false)
            toolbar.layoutIfNeeded()

            let library = UIHostingController(rootView: HStack(spacing: 12) {
                HonbakoLibraryControlButton(title: "Search", systemImage: "magnifyingglass", action: {})
                HonbakoLibraryControlButton(title: "Settings", systemImage: "gearshape", action: {})
            }.padding(8))
            root.addChild(library)
            library.view.backgroundColor = .clear
            library.view.frame = CGRect(x: 242, y: 380, width: 124, height: 64)
            root.view.addSubview(library.view)
            library.didMove(toParent: root)
            await settle(fixture.window)

            let surfaces = toolbar.subviews.compactMap { $0 as? UIVisualEffectView }
            XCTAssertEqual(surfaces.count, 3)
            for surface in surfaces {
                let effect = try XCTUnwrap(surface.effect as? UIGlassEffect)
                let tint = try XCTUnwrap(effect.tintColor?.resolvedColor(with: fixture.window.traitCollection))
                XCTAssertEqual(try channels(tint).alpha, 0.619, accuracy: 0.0001)
                XCTAssertEqual(surface.alpha, 1, "Glass tint must carry translucency; the entire surface must not fade")
                XCTAssertEqual(surface.contentView.alpha, 1)
            }
            XCTAssertEqual(toolbar.alpha, 1)
            XCTAssertEqual(scrubber.alpha, 1)
            XCTAssertTrue(descendants(toolbar, of: UIButton.self).allSatisfy { $0.alpha == 1 })
            let badge = try XCTUnwrap(scrubber.subviews.first { $0.accessibilityIdentifier == "Sumi.Reader.PagePosition" })
            XCTAssertEqual(try channels(XCTUnwrap(badge.backgroundColor).resolvedColor(with: fixture.window.traitCollection)).alpha, 1,
                           "The page number badge retains an opaque contrast surface")
            attach(try snapshot(fixture.window), name: "reader-glass-and-library-controls-\(name(style))")
        }
        let highContrast = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: .dark),
                                                         UITraitCollection(accessibilityContrast: .high)])
        XCTAssertEqual(try channels(HonbakoPalette.glassTintUIColor.resolvedColor(with: highContrast)).alpha, 1,
                       "Increased contrast restores a solid tint")
    }

    private func assertReadableAppearances(_ item: UINavigationItem, traits: UITraitCollection) throws {
        for (name, candidate) in [("standard", item.standardAppearance), ("compact", item.compactAppearance),
                                  ("scroll edge", item.scrollEdgeAppearance), ("compact scroll edge", item.compactScrollEdgeAppearance)] {
            let appearance = try XCTUnwrap(candidate, "Missing \(name) reader appearance")
            XCTAssertNil(appearance.backgroundEffect, "\(name) must not depend on blurring the page for contrast")
            let background = try XCTUnwrap(appearance.backgroundColor).resolvedColor(with: traits)
            XCTAssertEqual(try channels(background).alpha, 1, accuracy: 0.0001,
                           "\(name) must protect the title from both white and black artwork")
            let title = try XCTUnwrap(appearance.titleTextAttributes[.foregroundColor] as? UIColor).resolvedColor(with: traits)
            XCTAssertGreaterThanOrEqual(try contrast(title, on: background), 4.5)
            if #available(iOS 26.0, *) {
                let subtitle = try XCTUnwrap(appearance.subtitleTextAttributes[.foregroundColor] as? UIColor).resolvedColor(with: traits)
                // Native secondary metadata must keep perceptible contrast;
                // the render/OCR check also verifies the actual small subtitle.
                XCTAssertGreaterThanOrEqual(try contrast(subtitle, on: background), 3)
            }
        }
    }

    private func makeWindow(root: UIViewController, style: UIUserInterfaceStyle) throws -> ChromeWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKey = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.overrideUserInterfaceStyle = style
        window.traitOverrides.accessibilityContrast = .normal
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.loadViewIfNeeded()
        return ChromeWindow(window: window, previousKey: previousKey)
    }

    private func settle(_ window: UIWindow) async {
        for _ in 0..<8 {
            window.layoutIfNeeded()
            window.rootViewController?.view.setNeedsLayout()
            window.rootViewController?.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    private func snapshot(_ window: UIWindow) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
    }

    private func recognizedText(_ image: UIImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined().lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func practiceThumbnail() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 120, height: 180)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 180))
            UIColor.black.setStroke()
            for y in stride(from: 12, through: 136, by: 62) {
                let panel = UIBezierPath(rect: CGRect(x: 12, y: y, width: 96, height: 48))
                panel.lineWidth = 4
                panel.stroke()
            }
        }
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func name(_ style: UIUserInterfaceStyle) -> String { style == .dark ? "dark" : "light" }

    private func descendants<T: UIView>(_ view: UIView, of type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, of: type) }
    }

    private func channels(_ color: UIColor) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return (red, green, blue, alpha)
    }

    private func contrast(_ foreground: UIColor, on background: UIColor) throws -> CGFloat {
        let ink = try channels(foreground), paper = try channels(background)
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let red = ink.red * ink.alpha + paper.red * (1 - ink.alpha)
        let green = ink.green * ink.alpha + paper.green * (1 - ink.alpha)
        let blue = ink.blue * ink.alpha + paper.blue * (1 - ink.alpha)
        let inkLuminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        let paperLuminance = 0.2126 * linear(paper.red) + 0.7152 * linear(paper.green) + 0.0722 * linear(paper.blue)
        return (max(inkLuminance, paperLuminance) + 0.05) / (min(inkLuminance, paperLuminance) + 0.05)
    }
}

@MainActor
private struct ChromeWindow {
    let window: UIWindow
    let previousKey: UIWindow?

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        previousKey?.makeKey()
    }
}

@MainActor
private final class ChromeArtworkView: UIView {
    enum Backdrop: String, CaseIterable { case white, black, checkerboard }
    var backdrop = Backdrop.white { didSet { setNeedsDisplay() } }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor((backdrop == .black ? UIColor.black : UIColor.white).cgColor)
        context.fill(bounds)
        if backdrop == .checkerboard {
            context.setFillColor(UIColor.black.cgColor)
            for row in 0...Int(bounds.height / 24) {
                for column in 0...Int(bounds.width / 24) where (row + column).isMultiple(of: 2) {
                    context.fill(CGRect(x: column * 24, y: row * 24, width: 24, height: 24))
                }
            }
        }
    }
}
