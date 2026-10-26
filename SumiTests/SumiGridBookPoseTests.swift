@testable import Sumi
import Testing
import simd
import UIKit

@MainActor
struct SumiGridBookPoseTests {
    @Test("Every grid book stands upright with the same small depth-revealing angle")
    func stableClosedVolume() {
        let upright = SumiGridBookPose(seed: 0)
        for seed in UInt64(0)..<100 {
            let pose = SumiGridBookPose(seed: seed)
            #expect(pose == upright)
            #expect(pose.pitch == 0 && pose.roll == 0)
            #expect(abs(pose.yaw - 12 * .pi / 180) < 0.00001)
            #expect(simd_length(pose.orientation.act([0, 1, 0]) - SIMD3<Float>(0, 1, 0)) < 0.00001)
            let frame = pose.normalizedRenderingFrame
            #expect(frame.width > 0.6 && frame.height > 0.8)
            #expect(CGRect(x: 0, y: 0, width: 1, height: 1).contains(frame))
            #expect(abs(frame.midX - 0.5) < 0.02)
            #expect(abs(frame.midY - 0.5) < 0.02)
        }
    }

    @Test("Pickup endpoints preserve the closed pose and become flat only when the book opens")
    func matchingPickupPose() {
        let pose = SumiGridBookPose(seed: 0xADC0)
        let closed = pose.orientation(progress: 0)
        let open = pose.orientation(progress: 1)
        #expect(abs(closed.real - pose.orientation.real) < 0.00001)
        #expect(abs(open.real - 1) < 0.00001)
        #expect(abs(open.imag.x) + abs(open.imag.y) + abs(open.imag.z) < 0.00001)
        #expect(SumiGridBookPose.canvasHeight == SumiGridBookPose.cameraHalfHeight * 2)
    }
}
