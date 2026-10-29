@testable import Sumi
import MetalKit
import UIKit
import XCTest

@MainActor
final class SumiFingerPaperDesignTests: XCTestCase {
    func testFingerDrivenPaperCapturesAndUpdateCost() async throws {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let guides = HonbakoGuideBook.allCases
        let images = (0..<4).map { index -> UIImage in
            HonbakoGuideRenderer.render(guide: guides[index % guides.count], page: index % 3 + 1, language: "en")
        }
        let turn = SumiPageCurlView(frame: bounds, oldImages: Array(images.prefix(2)), newImages: Array(images.suffix(2)), rightToLeft: true)
        let host = UIViewController(); host.view.backgroundColor = .black; host.view.addSubview(turn)
        let window = UIWindow(frame: bounds); window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let hardwarePaper = turn.subviews.compactMap { $0 as? SumiPageCurlMetalRenderer }.first
        if SumiPageCurlMetalRenderer.isAvailable { XCTAssertNotNil(hardwarePaper) }
        for (name, y, translation) in [
            ("top-corner", CGFloat(80), CGPoint(x: -250, y: 75)),
            ("bottom-corner", 620, CGPoint(x: -250, y: -75)),
            ("mid-turn", 620, CGPoint(x: -600, y: -50))
        ] {
            turn.beginDragging(at: CGPoint(x: 950, y: y))
            let p = turn.drag(translation: translation)
            turn.update(progress: p)
            let image = try capturePaper(host: host, turn: turn, hardware: hardwarePaper, bounds: bounds)
            let capture = XCTAttachment(image: image); capture.name = name; capture.lifetime = .keepAlways; add(capture)
        }
        turn.beginDragging(at: CGPoint(x: 950, y: 620))
        for step in 0...8 {
            let travel = CGFloat(step) / 8
            let p = turn.drag(translation: CGPoint(x: -900 * travel, y: -70 * sin(.pi * travel)))
            turn.update(progress: p)
            let image = try capturePaper(host: host, turn: turn, hardware: hardwarePaper, bounds: bounds)
            let capture = XCTAttachment(image: image)
            capture.name = "paper-sequence-\(step)"
            capture.lifetime = .keepAlways
            add(capture)
        }
        if let hardwarePaper {
            let data = try JSONSerialization.data(withJSONObject: hardwarePaper.renderingMemoryInfo, options: .sortedKeys)
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "paper-rendering-memory"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let started = CACurrentMediaTime()
        for frame in 0..<120 { turn.update(progress: CGFloat(frame % 60) / 60) }
        let cost = (CACurrentMediaTime() - started) / 120
        // This bounds CPU mesh submission only; it does not claim rendered FPS.
        XCTAssertLessThan(cost, 1.0 / 60, "Paper mesh submission must fit a frame on this test host")
        print("Finger paper CPU submission average: \(cost * 1000) ms")
    }

    private func capturePaper(host: UIViewController, turn: SumiPageCurlView,
                              hardware: SumiPageCurlMetalRenderer?, bounds: CGRect) throws -> UIImage {
        // UIView snapshots can cache old CAMetalLayer drawables in component
        // windows. Read the exact current production GPU pass instead.
        let moving = try hardware.map { try XCTUnwrap($0.renderSnapshot()) }
        let wasHidden = hardware?.isHidden ?? false
        let handoff = turn.layer.sublayers?.first { $0.name == "sumi.reader.initial-paper-handoff" }
        let handoffHidden = handoff?.isHidden ?? true
        hardware?.isHidden = true
        handoff?.isHidden = true
        defer { hardware?.isHidden = wasHidden; handoff?.isHidden = handoffHidden }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true; format.preferredRange = .standard
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            host.view.layer.render(in: context.cgContext)
            moving?.draw(in: bounds)
        }
    }
}
