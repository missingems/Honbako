@testable import Sumi
import CoreGraphics
import Testing
import UIKit

@MainActor
@Suite struct HonbakoPageCoachingGeometryTests {
    private typealias Models = HonbakoPageCoachingModels
    private typealias Geometry = HonbakoPageCoachingOverlayView.Geometry

    @Test("Normalized marks map into the actual aspect-fit page frame")
    func mapsPageCoordinates() throws {
        let page = CGRect(x: 20, y: 70, width: 300, height: 450)
        let point = try #require(Geometry.point(.init(x: 0.5, y: 0.25), in: page))
        #expect(point == CGPoint(x: 170, y: 182.5))
        let frame = try #require(Geometry.rect(.init(x: 0.2, y: 0.1, width: 0.4, height: 0.3), in: page))
        #expect(frame == CGRect(x: 80, y: 115, width: 120, height: 135))
    }

    @Test("Resizing or rotating the page recomputes marks from the same normalized anchors")
    func adaptsToNewImageGeometry() throws {
        let box = Models.Rect(x: 0.25, y: 0.2, width: 0.5, height: 0.4)
        let portrait = try #require(Geometry.rect(box, in: CGRect(x: 0, y: 0, width: 300, height: 450)))
        let landscape = try #require(Geometry.rect(box, in: CGRect(x: 0, y: 0, width: 600, height: 400)))
        #expect(portrait.midX / 300 == landscape.midX / 600)
        #expect(portrait.midY / 450 == landscape.midY / 400)
        #expect(portrait.width / 300 == landscape.width / 600)
        #expect(portrait.height / 450 == landscape.height / 400)
    }

    @Test("Invalid or out-of-page coaching coordinates cannot create stray drawing layers")
    func rejectsInvalidCoordinates() {
        let page = CGRect(x: 0, y: 0, width: 300, height: 450)
        #expect(Geometry.point(.init(x: -0.1, y: 0.2), in: page) == nil)
        #expect(Geometry.point(.init(x: .nan, y: 0.2), in: page) == nil)
        #expect(Geometry.rect(.init(x: 0.9, y: 0.2, width: 0.2, height: 0.2), in: page) == nil)
        #expect(Geometry.rect(.init(x: 0, y: 0, width: 0, height: 0.2), in: page) == nil)
        #expect(Geometry.rect(.init(x: 0, y: 0, width: 1, height: 1), in: .zero) == nil)
        #expect(Geometry.rect(.init(x: 0, y: 0, width: 1, height: 1), in: .infinite) == nil)
    }

    @Test("Boxes, arrows and strokes produce page-anchored vector paths")
    func drawsSupportedMarks() throws {
        let page = CGRect(x: 0, y: 0, width: 300, height: 450)
        let box = Models.Annotation(id: "box", type: .box,
            rect: .init(x: 0.2, y: 0.1, width: 0.4, height: 0.3))
        let boxPath = try #require(Geometry.path(for: box, in: page))
        #expect(boxPath.boundingBoxOfPath == CGRect(x: 60, y: 45, width: 120, height: 135))
        let arrow = Models.Annotation(id: "arrow", type: .arrow,
            from: .init(x: 0.1, y: 0.2), to: .init(x: 0.8, y: 0.7))
        let arrowPath = try #require(Geometry.path(for: arrow, in: page))
        #expect(page.contains(arrowPath.boundingBoxOfPath))
        let stroke = Models.Annotation(id: "stroke", type: .stroke,
            points: [.init(x: 0.1, y: 0.2), .init(x: 0.5, y: 0.6), .init(x: 0.8, y: 0.3)])
        let strokePath = try #require(Geometry.path(for: stroke, in: page))
        #expect(strokePath.boundingBoxOfPath == CGRect(x: 30, y: 90, width: 210, height: 180))
        let zeroArrow = Models.Annotation(id: "empty", type: .arrow,
            from: .init(x: 0.1, y: 0.2), to: .init(x: 0.1, y: 0.2))
        #expect(Geometry.path(for: zeroArrow, in: page) == nil)
    }

    @Test("Tiny valid labels never send null or infinite padded geometry to UIKit")
    func tinyLabelPaddingStaysSafe() throws {
        let tiny = Models.Rect(x: 0.1, y: 0.2, width: 0.001, height: 0.001)
        #expect(HonbakoPageCoachingPolicy.valid(tiny))
        for page in [CGRect(x: 0, y: 0, width: 600, height: 900),
                     CGRect(x: 0, y: 0, width: 900, height: 600),
                     CGRect(x: 0, y: 0, width: 0.6, height: 0.9)] {
            let projected = try #require(Geometry.rect(tiny, in: page))
            #expect(Geometry.labelContentFrame(in: CGRect(origin: .zero, size: projected.size)) == nil)
        }
        for bounds in [CGRect.zero, .null, .infinite,
                       CGRect(x: 0, y: 0, width: 12, height: 30),
                       CGRect(x: 0, y: 0, width: 30, height: 8)] {
            #expect(Geometry.labelContentFrame(in: bounds) == nil)
        }
        let normal = try #require(Geometry.labelContentFrame(in: CGRect(x: 0, y: 0, width: 100, height: 40)))
        #expect(normal == CGRect(x: 6, y: 4, width: 88, height: 32))
        #expect(Geometry.valid(normal))
    }

    @Test("Coaching does not intercept reading, page flipping, or pinch gestures")
    func overlayPassesTouchesThrough() {
        let overlay = HonbakoPageCoachingOverlayView()
        overlay.frame = CGRect(x: 0, y: 0, width: 300, height: 450)
        #expect(!overlay.isUserInteractionEnabled)
        #expect(overlay.hitTest(CGPoint(x: 100, y: 100), with: nil) == nil)
        #expect(overlay.isHidden)
        #expect(overlay.accessibilityElements?.isEmpty == true)
    }
}
