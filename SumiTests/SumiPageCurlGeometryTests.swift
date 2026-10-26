@testable import Sumi
import Testing
import UIKit

@Suite struct SumiPageCurlGeometryTests {
    @Test("Paper starts and finishes at exact flat leaves with the binding pinned")
    func flatEndpoints() {
        for step in 0...20 {
            let u = CGFloat(step) / 20
            let first = SumiPageCurlGeometry.sample(at: u, progress: 0, width: 360)
            let last = SumiPageCurlGeometry.sample(at: u, progress: 1, width: 360)
            #expect(abs(first.x - 360 * u) < 0.0001)
            #expect(abs(last.x + 360 * u) < 0.0001)
            #expect(first.elevation == 0)
            #expect(last.elevation == 0)
            let bound = SumiPageCurlGeometry.sample(at: 0, progress: u, width: 360)
            #expect(bound.x == 0)
            #expect(bound.elevation == 0)
        }
    }

    @Test("The leaf bends continuously rather than turning as a flat card")
    func flexiblePaper() {
        let inner = SumiPageCurlGeometry.sample(at: 0.1, progress: 0.45, width: 360)
        let outer = SumiPageCurlGeometry.sample(at: 0.9, progress: 0.45, width: 360)
        #expect(outer.angle - inner.angle > 0.8)
        #expect(outer.elevation > inner.elevation)
        for step in 1..<100 {
            let p = CGFloat(step) / 100
            for u in stride(from: CGFloat(0), through: 1, by: 0.025) {
                let value = SumiPageCurlGeometry.sample(at: u, progress: p, width: 360)
                #expect(value.x.isFinite && value.elevation.isFinite && value.angle.isFinite)
                #expect(value.elevation >= 0)
            }
        }
    }

    @Test("Paper arc length stays constant at every stage of the turn")
    func preservesArcLength() {
        let width: CGFloat = 360
        let steps = 1000
        for progress: CGFloat in [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1] {
            var previous = SumiPageCurlGeometry.sample(at: 0, progress: progress, width: width)
            var length: CGFloat = 0
            for step in 1...steps {
                let next = SumiPageCurlGeometry.sample(at: CGFloat(step) / CGFloat(steps),
                                                       progress: progress, width: width)
                length += hypot(next.x - previous.x, next.elevation - previous.elevation)
                previous = next
            }
            #expect(abs(length - width) < 0.001)
        }
    }

    @Test("A lifted leaf casts a separate light projection onto the spread")
    func castShadowProjection() {
        let bounds = CGRect(x: 0, y: 0, width: 720, height: 600)
        for sign: CGFloat in [-1, 1] {
            let flat = SumiPageCurlGeometry.sample(at: 0.8, progress: 0, width: 360)
            let flatShadow = SumiPageCurlGeometry.castShadow(flat, y: 100, hinge: 360, sign: sign)
            let flatPaper = SumiPageCurlGeometry.projected(flat, y: 100, bounds: bounds, hinge: 360, sign: sign)
            #expect(flatShadow == flatPaper)
            for progress: CGFloat in [0.1, 0.35, 0.5, 0.7, 0.9] {
                let raised = SumiPageCurlGeometry.sample(at: 0.8, progress: progress, width: 360)
                let shadow = SumiPageCurlGeometry.castShadow(raised, y: 100, hinge: 360, sign: sign)
                let paper = SumiPageCurlGeometry.projected(raised, y: 100, bounds: bounds, hinge: 360, sign: sign)
                #expect(shadow.x.isFinite && shadow.y.isFinite)
                #expect(shadow.y > 100)
                #expect(hypot(shadow.x - paper.x, shadow.y - paper.y) > 1)
                // Fixed room lighting falls rightwards, whichever way a leaf
                // turns. It is not another dark layer on the printed artwork.
                #expect(shadow.x > 360 + sign * raised.x)
            }
            let binding = SumiPageCurlGeometry.sample(at: 0, progress: 0.5, width: 360)
            #expect(SumiPageCurlGeometry.castShadow(binding, y: 100, hinge: 360, sign: sign) == CGPoint(x: 360, y: 100))
        }
    }

    @Test("A folded-back silhouette cannot cancel the shadow below the raised paper")
    func overlappingShadow() {
        var points: [CGPoint] = []
        for step in 0...56 {
            let sample = SumiPageCurlGeometry.sample(at: CGFloat(step) / 56, progress: 0.5, width: 360)
            points.append(SumiPageCurlGeometry.castShadow(sample, y: 0, hinge: 360, sign: 1))
            points.append(SumiPageCurlGeometry.castShadow(sample, y: 600, hinge: 360, sign: 1))
        }
        let footprint = SumiPageCurlGeometry.shadowFootprint(points)
        #expect(footprint.contains(CGPoint(x: 440, y: 300)))
        #expect(!footprint.contains(CGPoint(x: 355, y: 300)))
        #expect(!footprint.contains(CGPoint(x: 460, y: 300)))
    }

    @Test("The projected mesh maps all four texture corners without a mid-turn texture jump")
    func homographyCorners() {
        let corners = [CGPoint(x: 25, y: 12), CGPoint(x: 41, y: 18),
                       CGPoint(x: 40, y: 490), CGPoint(x: 24, y: 500)]
        let transform = SumiPageCurlGeometry.transform(topLeft: corners[0], topRight: corners[1],
                                                      bottomRight: corners[2], bottomLeft: corners[3])
        let local = [CGPoint.zero, CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        for (source, expected) in zip(local, corners) {
            let divisor = source.x * transform.m14 + source.y * transform.m24 + transform.m44
            let x = (source.x * transform.m11 + source.y * transform.m21 + transform.m41) / divisor
            let y = (source.x * transform.m12 + source.y * transform.m22 + transform.m42) / divisor
            #expect(abs(x - expected.x) < 0.0001)
            #expect(abs(y - expected.y) < 0.0001)
        }
    }
}
