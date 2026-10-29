@testable import Sumi
import AidokuRunner
import SwiftUI
import UIKit
import XCTest

@MainActor
final class HonbakoFinishedDateClippingTests: XCTestCase {
    func testFinishedCoversStayWithinEitherSafeAreaEdge() async throws {
        let date = Date(timeIntervalSince1970: 1_793_232_000)
        let books = try [HonbakoGuideBook.find, .connect].map {
            SumiBook(manga: try HonbakoGuideLibrary.makeManga($0), isInLibrary: true, finishedReadingAt: date)
        }
        await SumiCoverArtworkLoader.shared.prepare(books)
        for trailing in [false, true] {
            let content = VStack(spacing: 0) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                    HonbakoLibrarySectionView(books: books, openingBookID: nil, openBook: { _, _ in })
                }
                Spacer(minLength: 0)
            }
            .background { Color.black.ignoresSafeArea() }
            .environment(\.colorScheme, .dark)
            let host = UIHostingController(rootView: content)
            host.overrideUserInterfaceStyle = .dark
            host.additionalSafeAreaInsets = UIEdgeInsets(top: 60, left: trailing ? 0 : 100, bottom: 30, right: trailing ? 100 : 0)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 900))
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            for _ in 0..<8 {
                window.layoutIfNeeded(); host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(40))
            }
            let covers = descendants(host.view).compactMap { $0 as? SumiGridBookView }
                .sorted { $0.convert($0.bounds, to: host.view).minX < $1.convert($1.bounds, to: host.view).minX }
            XCTAssertEqual(covers.count, 2)
            let cover = try XCTUnwrap(trailing ? covers.last : covers.first)
            let frame = cover.convert(cover.bounds, to: host.view)
            let edge = trailing ? frame.maxX : frame.minX
            XCTAssertEqual(edge, trailing ? host.view.bounds.maxX - 100 : 100, accuracy: 1)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.preferredRange = .standard
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
                XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
            }
            let y = frame.maxY - 8
            // Finished covers must keep the side-control safe area clear.
            for distance in [12.0, 40.0, 80.0] {
                let outside = try pixel(image, at: CGPoint(x: edge + (trailing ? distance : -distance), y: y))
                XCTAssertLessThanOrEqual(outside.prefix(3).map(Int.init).max() ?? 255, 8,
                                         "Finished covers must stop before the side-control safe area")
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = trailing ? "Finished covers before trailing safe area" : "Finished covers after leading safe area"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func pixel(_ image: UIImage, at point: CGPoint) throws -> [UInt8] {
        let source = try XCTUnwrap(image.cgImage)
        let x = Int(point.x.rounded()), y = Int(point.y.rounded())
        XCTAssertTrue((0..<source.width).contains(x) && (0..<source.height).contains(y))
        let cropped = try XCTUnwrap(source.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }
}
