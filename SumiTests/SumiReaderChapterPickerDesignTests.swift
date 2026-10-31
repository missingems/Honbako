@testable import Sumi
import AidokuRunner
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class SumiReaderChapterPickerDesignTests: XCTestCase {
    func testLongChapterListOpensAtTheCurrentReadingChapter() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let chapters = (1...120).reversed().map { number in
            AidokuRunner.Chapter(key: "chapter-\(number)", title: "A new day", chapterNumber: Float(number))
        }
        for dark in [false, true] {
            let content = SumiReaderChaptersView(chapters: chapters, currentKey: "chapter-43",
                currentPage: 12, currentTotalPages: 24, canRead: { _ in true }, select: { _, _ in }, close: {})
                .environment(\.colorScheme, dark ? .dark : .light)
            let host = UIHostingController(rootView: content)
            host.overrideUserInterfaceStyle = dark ? .dark : .light
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            for _ in 0..<20 {
                window.layoutIfNeeded()
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
            }
            let request = VNRecognizeTextRequest()
            try VNImageRequestHandler(cgImage: try XCTUnwrap(image.cgImage)).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ").lowercased().replacingOccurrences(of: " ", with: "")
            XCTAssertTrue(text.contains("chapter43"), "The current reading chapter must be in view without scrolling: \(text)")
            XCTAssertFalse(text.contains("chapter120"), "The picker must scroll past the first chapter to the saved reading position")
            let attachment = XCTAttachment(image: image)
            attachment.name = dark ? "chapters-current-highlight-dark" : "chapters-current-highlight-light"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
    func testConfirmedUnavailableChaptersRemainListedAndUseGrayTitles() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let source = AidokuRunner.Source.local()
        let manga = AidokuRunner.Manga(sourceKey: source.key, key: "chapter-gray-" + UUID().uuidString, title: "Availability")
        let chapters = [AidokuRunner.Chapter(key: "available", chapterNumber: 3),
                        AidokuRunner.Chapter(key: "confirmed-empty", chapterNumber: 2),
                        AidokuRunner.Chapter(key: "provider-unavailable", chapterNumber: 1, locked: true)]
        let key = SumiChapterPageListCache.Key(source: source, manga: manga, chapter: chapters[1])
        HonbakoChapterAvailability.shared.record(.unavailable, for: key, expires: .now.addingTimeInterval(300))
        defer { HonbakoChapterAvailability.shared.clear(key) }
        let content = SumiReaderChaptersView(chapters: chapters, currentKey: "available", source: source, manga: manga,
            canRead: { !$0.locked }, select: { _, _ in }, close: {}).environment(\.colorScheme, .light)
        let host = UIHostingController(rootView: content)
        host.overrideUserInterfaceStyle = .light
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 1100)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<20 {
            window.layoutIfNeeded(); host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        let cgImage = try XCTUnwrap(image.cgImage)
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        var titles: [String: CGRect] = [:]
        for observation in request.results ?? [] {
            let text = observation.topCandidates(1).first?.string.lowercased().filter { $0.isLetter || $0.isNumber }
            if let text, ["chapter1", "chapter2", "chapter3"].contains(text) { titles[text] = observation.boundingBox }
        }
        let available = try titleInkLuminance(cgImage, box: XCTUnwrap(titles["chapter3"]))
        for name in ["chapter1", "chapter2"] {
            let unavailable = try titleInkLuminance(cgImage, box: XCTUnwrap(titles[name]))
            XCTAssertGreaterThan(unavailable - available, 0.1,
                                 "Both provider metadata and confirmed empty pages must gray only their own chapter title")
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "chapters-confirmed-unavailable-gray"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func titleInkLuminance(_ image: CGImage, box: CGRect) throws -> CGFloat {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let rect = CGRect(x: box.minX * CGFloat(width), y: (1 - box.maxY) * CGFloat(height),
                          width: box.width * CGFloat(width), height: box.height * CGFloat(height))
        var values: [CGFloat] = []
        for y in max(0, Int(rect.minY))..<min(height, Int(ceil(rect.maxY))) {
            for x in max(0, Int(rect.minX))..<min(width, Int(ceil(rect.maxX))) {
                let offset = (y * width + x) * 4
                values.append((0.2126 * CGFloat(bytes[offset]) + 0.7152 * CGFloat(bytes[offset + 1])
                    + 0.0722 * CGFloat(bytes[offset + 2])) / 255)
            }
        }
        values.sort()
        XCTAssertFalse(values.isEmpty)
        return values[values.count / 10]
    }

}
