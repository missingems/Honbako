@testable import Sumi
import CoreGraphics
import Testing

struct SumiBookReturnPoseTests {
    private let origin = CGRect(x: 24, y: 48, width: 152, height: 200)
    private let hovering = CGRect(x: 380, y: 92, width: 304, height: 400)
    private let viewport = CGRect(x: 0, y: 0, width: 1000, height: 700)

    @Test("A returning cover closes while travelling toward its actual slot without a hover phase")
    func closesDuringReturn() {
        for paired in [false, true] {
            let destinationBinding = paired ? viewport.midX : viewport.minX
            for progress: CGFloat in [0.8, 0.5, 0.35, 0.175] {
                let pose = SumiBookReturnPose(progress: progress, origin: origin)
                #expect(pose.sourceFrame == origin)
                #expect(pose.openness == progress, "The cover must keep closing throughout travel")
                #expect(abs(pose.gridDimming - 0.68 * progress) < 0.000001)
                let frame = pose.paperFrame(in: viewport, paired: paired)
                let binding = paired ? frame.midX : frame.minX
                let expectedBinding = origin.minX + (destinationBinding - origin.minX) * progress
                #expect(abs(binding - expectedBinding) < 0.000001,
                        "There is no intermediate binding at the centered hover pose")
                #expect(abs(frame.midY - (origin.midY + (viewport.midY - origin.midY) * progress)) < 0.000001)
                #expect(frame.height > origin.height && frame.height < viewport.height)
            }
        }
    }

    @Test("Reversing an interactive dismissal retraces the same paper and restores the full reader")
    func reversibleDirectPath() {
        for paired in [false, true] {
            let first = SumiBookReturnPose(progress: 0.72, origin: origin)
            _ = SumiBookReturnPose(progress: 0.4, origin: origin)
            let reversed = SumiBookReturnPose(progress: 0.72, origin: origin)
            #expect(first.paperFrame(in: viewport, paired: paired) == reversed.paperFrame(in: viewport, paired: paired))
            #expect(first.openness == reversed.openness)
            let restored = SumiBookReturnPose(progress: 1, origin: origin)
            assertEqual(restored.paperFrame(in: viewport, paired: paired), viewport)
            #expect(restored.openness == 1)
        }
    }

    @Test("Canceling a partial opening preserves its exact visible angle and geometry before returning")
    func partialOpeningHasNoJump() {
        for paired in [false, true] {
            for step in 0...20 {
                let visibleOpenness = CGFloat(step) / 20
                let initialFrame = SumiBookMotion.paperFrame(source: hovering, destination: viewport,
                                                            paired: paired, progress: visibleOpenness)
                let initial = SumiBookReturnPose(progress: 1, origin: origin, initialOpenness: visibleOpenness)
                #expect(initial.openness == visibleOpenness)
                assertEqual(initial.paperFrame(in: viewport, paired: paired, startingAt: initialFrame), initialFrame)

                let half = SumiBookReturnPose(progress: 0.5, origin: origin, initialOpenness: visibleOpenness)
                #expect(half.openness == visibleOpenness / 2)
                let frame = half.paperFrame(in: viewport, paired: paired, startingAt: initialFrame)
                let endFrame = SumiBookMotion.paperFrame(source: origin, destination: viewport, paired: paired, progress: 0)
                #expect(abs(frame.midX - (initialFrame.midX + endFrame.midX) / 2) < 0.000001)
                #expect(abs(frame.midY - (initialFrame.midY + endFrame.midY) / 2) < 0.000001)
                let end = SumiBookReturnPose(progress: 0, origin: origin, initialOpenness: visibleOpenness)
                assertEqual(end.paperFrame(in: viewport, paired: paired, startingAt: initialFrame), endFrame)
            }
        }
    }

    @Test("Canceling before the first paper draw lowers the exact cover directly to its original slot")
    func closedCoverReturn() {
        let initial = SumiBookReturnPose(progress: 1, origin: origin, initialOpenness: 0)
        assertEqual(initial.coverFrame(startingAt: hovering), hovering)
        let half = SumiBookReturnPose(progress: 0.5, origin: origin, initialOpenness: 0)
        let frame = half.coverFrame(startingAt: hovering)
        #expect(abs(frame.midX - (origin.midX + hovering.midX) / 2) < 0.000001)
        #expect(abs(frame.midY - (origin.midY + hovering.midY) / 2) < 0.000001)
        #expect(half.openness == 0)
        let end = SumiBookReturnPose(progress: 0, origin: origin, initialOpenness: 0)
        assertEqual(end.coverFrame(startingAt: hovering), origin)
    }

    @Test("The last closing leaf lands on the current source measurement in every corner")
    func landsAtLiveOrigin() {
        for slot in [origin, CGRect(x: 780, y: 460, width: 152, height: 200),
                     CGRect(x: 290, y: 110, width: 45, height: 66)] {
            for paired in [false, true] {
                let returned = SumiBookReturnPose(progress: 0, origin: slot)
                let frame = returned.paperFrame(in: viewport, paired: paired)
                let cover = paired
                    ? CGRect(x: frame.midX, y: frame.minY, width: frame.width / 2, height: frame.height)
                    : frame
                assertEqual(cover, slot)
                #expect(returned.gridDimming == 0)
            }
        }
    }

    @Test("Overshooting gestures clamp to the open reader and original cover endpoints")
    func clampsGestureRange() {
        for progress: CGFloat in [-10, -0.1, 0] {
            let pose = SumiBookReturnPose(progress: progress, origin: origin)
            #expect(pose.openness == 0)
            #expect(pose.sourceFrame == origin)
            #expect(pose.gridDimming == 0)
        }
        for progress: CGFloat in [1, 1.1, 10] {
            let pose = SumiBookReturnPose(progress: progress, origin: origin)
            #expect(pose.openness == 1)
            #expect(pose.sourceFrame == origin)
            #expect(pose.gridDimming == 0.68)
        }
    }

    private func assertEqual(_ actual: CGRect, _ expected: CGRect) {
        #expect(abs(actual.minX - expected.minX) < 0.000001)
        #expect(abs(actual.minY - expected.minY) < 0.000001)
        #expect(abs(actual.width - expected.width) < 0.000001)
        #expect(abs(actual.height - expected.height) < 0.000001)
    }
}
