@testable import Sumi
import Testing
import UIKit
import simd

struct SumiBookMotionTests {
    @Test("Pinch contraction progressively closes the book and expansion retraces the same path")
    func pinchIntent() {
        #expect(SumiBookMotion.pinchProgress(scale: 1.2) == 0)
        #expect(SumiBookMotion.pinchProgress(scale: 1) == 0)
        #expect(abs(SumiBookMotion.pinchProgress(scale: 0.775) - 0.5) < 0.000001)
        #expect(abs(SumiBookMotion.pinchProgress(scale: 0.55) - 1) < 0.000001)
        #expect(SumiBookMotion.pinchProgress(scale: 0.2) == 1)
        #expect(!SumiBookMotion.completes(swipe: SumiBookMotion.pinchProgress(scale: 0.92), velocity: 0))
        #expect(SumiBookMotion.completes(swipe: SumiBookMotion.pinchProgress(scale: 0.68), velocity: 0))
        #expect(SumiBookMotion.pinchVelocity(-0.45) == 1)
        #expect(SumiBookMotion.pinchVelocity(0.45) == -1)
    }

    @Test("Book closing starts moving immediately and predicts pinch completion")
    func swipeIntent() {
        #expect(SumiBookMotion.closeProgress(0.08) == 0.08)
        #expect(abs(SumiBookMotion.closeProgress(0.55) - 0.55) < 0.001)
        #expect(SumiBookMotion.closeProgress(2) == 1)
        #expect(!SumiBookMotion.completes(swipe: 0.25, velocity: 0))
        #expect(SumiBookMotion.completes(swipe: 0.25, velocity: 1.5))
        #expect(!SumiBookMotion.completes(swipe: 0.6, velocity: -1))
    }

    @Test("A short edge swipe returns on compact and wide displays while a nudge or reversal cancels")
    func shortBackSwipe() {
        for width: CGFloat in [320, 450, 1024] {
            #expect(SumiBookMotion.completesBackSwipe(travel: 82, velocity: 0, width: width))
            #expect(SumiBookMotion.completesBackSwipe(travel: 24, velocity: 500, width: width))
            #expect(!SumiBookMotion.completesBackSwipe(travel: 8, velocity: 1000, width: width))
            #expect(!SumiBookMotion.completesBackSwipe(travel: 82, velocity: -200, width: width))
            #expect(!SumiBookMotion.completesBackSwipe(travel: 20, velocity: 0, width: width))
        }
    }

    @Test("The same critically damped spring opens, closes, and cancels without overshooting")
    func reversibleSpring() {
        for from: CGFloat in [0, 0.3, 1] {
            for to: CGFloat in [0, 1] {
                #expect(abs(SumiBookMotion.spring(from: from, to: to, velocity: 4, time: 0) - from) < 0.000001)
                let end = SumiBookMotion.spring(from: from, to: to, velocity: 0, time: 0.7)
                #expect(abs(end - to) < 0.001)
                let middle = SumiBookMotion.spring(from: from, to: to, velocity: 0, time: 0.2)
                #expect(middle >= min(from, to) && middle <= max(from, to))
            }
        }
    }

    @Test("Camera magnification interpolates geometrically and keeps measured endpoints")
    func cameraScale() {
        #expect(SumiBookMotion.pointsPerUnit(sourceHeight: 200, destinationHeight: 800, progress: 0) == 200)
        #expect(SumiBookMotion.pointsPerUnit(sourceHeight: 200, destinationHeight: 800, progress: 0.5) == 400)
        #expect(SumiBookMotion.pointsPerUnit(sourceHeight: 200, destinationHeight: 800, progress: 1) == 800)
    }

    @Test("The front cover travels toward the reader and opens to the left")
    func coverOpensLeft() {
        let outerEdge = SIMD3<Float>(1, 0, 0)
        let halfway = simd_act(simd_quatf(angle: SumiBookMotion.coverAngle(progress: 0.5), axis: [0, 1, 0]), outerEdge)
        #expect(abs(halfway.x) < 0.001)
        #expect(halfway.z > 0.99)
        let open = simd_act(simd_quatf(angle: SumiBookMotion.coverAngle(progress: 1), axis: [0, 1, 0]), outerEdge)
        #expect(open.x < -0.99)
        #expect(abs(open.z) < 0.001)
    }

    @Test("A left-bound cover starts on the right leaf and the open book matches its native viewport")
    func leftBoundGeometry() {
        let source = CGRect(x: 230, y: 170, width: 204, height: 300)
        for destination in [CGRect(x: 0, y: 0, width: 1000, height: 700), CGRect(x: 0, y: 0, width: 450, height: 700)] {
            for paired in [false, true] {
                let closed = SumiBookMotion.paperFrame(source: source, destination: destination, paired: paired, progress: 0)
                let rightLeaf = paired ? CGRect(x: closed.midX, y: closed.minY, width: closed.width / 2, height: closed.height) : closed
                #expect(abs(rightLeaf.minX - source.minX) < 0.001)
                #expect(abs(rightLeaf.width - source.width) < 0.001)
                #expect(abs(rightLeaf.minY - source.minY) < 0.001)
                #expect(abs(rightLeaf.height - source.height) < 0.001)
                let open = SumiBookMotion.paperFrame(source: source, destination: destination, paired: paired, progress: 1)
                #expect(abs(open.minX - destination.minX) < 0.001)
                #expect(abs(open.minY - destination.minY) < 0.001)
                #expect(abs(open.width - destination.width) < 0.001)
                #expect(abs(open.height - destination.height) < 0.001)
            }
        }
    }
}
