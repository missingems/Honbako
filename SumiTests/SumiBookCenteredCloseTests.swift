@testable import Sumi
import Testing
import UIKit

@MainActor
struct SumiBookCenteredCloseTests {
    @Test("The normal cover closes at the middle before returning to every library corner")
    func centerThenReturn() throws {
        for viewport in [CGRect(x: 0, y: 0, width: 420, height: 900), CGRect(x: 0, y: 0, width: 1000, height: 700)] {
            for origin in [CGRect(x: 20, y: 40, width: 140, height: 210), CGRect(x: 260, y: 450, width: 140, height: 210)] {
                let started = SumiBookPinchPose(progress: 1, origin: origin, viewport: viewport)
                #expect(started.spreadFrame == viewport)
                #expect(started.fold == 0)
                for progress: CGFloat in [0.9, 0.7, 0.5, 0.32] {
                    let pose = SumiBookPinchPose(progress: progress, origin: origin, viewport: viewport)
                    #expect(abs(pose.coverFrame.midX - viewport.midX) < 0.001)
                    #expect(abs(pose.coverFrame.midY - viewport.midY) < 0.001)
                    #expect(pose.spreadFrame.midX == viewport.midX)
                }
                let closedAtCenter = SumiBookPinchPose(progress: 0.32, origin: origin, viewport: viewport)
                #expect(abs(closedAtCenter.fold - 1) < 0.001)
                #expect(abs(closedAtCenter.coverOpacity - 1) < 0.001)
                let returned = SumiBookPinchPose(progress: 0, origin: origin, viewport: viewport)
                #expect(abs(returned.coverFrame.minX - origin.minX) < 0.001)
                #expect(abs(returned.coverFrame.minY - origin.minY) < 0.001)
                #expect(abs(returned.coverFrame.width - origin.width) < 0.001)
                #expect(abs(returned.coverFrame.height - origin.height) < 0.001)
            }
        }
    }

    @Test("Pinch uses exactly the normal one-cover hinge and retraces it on cancellation")
    func oneCoverGeometry() throws {
        let viewport = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let image = UIGraphicsImageRenderer(size: viewport.size).image { _ in UIColor.blue.setFill(); UIRectFill(viewport) }
        let origin = CGRect(x: 24, y: 60, width: 140, height: 210)
        for paired in [false, true] {
            let pinch = try SumiBookStageView(frame: viewport, cover: image, spread: image, paired: paired, centeredClose: true)
            let normal = try SumiBookStageView(frame: viewport, cover: image, spread: image, paired: paired)
            let layers = try #require(pinch.layer.sublayers)
            #expect(layers.count == 2, "One stationary page and one hinged cover; never two folding halves")
            let stationary = try #require(layers.first)
            let hinge = try #require(layers.last)
            let normalHinge = try #require(normal.layer.sublayers?.last)
            for progress: CGFloat in [1, 0.8, 0.5, 0.32, 0.5, 0.8, 1] {
                let pose = SumiBookPinchPose(progress: progress, origin: origin, viewport: viewport)
                #expect(pinch.draw(progress: progress, source: origin, deltaTime: 1 / 60))
                #expect(normal.draw(progress: 1 - pose.fold, source: pose.coverFrame, deltaTime: 1 / 60))
                #expect(CATransform3DIsIdentity(stationary.transform), "The back never folds in from the opposite side")
                #expect(CATransform3DEqualToTransform(hinge.transform, normalHinge.transform))
                #expect(hinge.position == normalHinge.position && hinge.bounds == normalHinge.bounds)
            }
            #expect(hinge.position.x == (paired ? viewport.midX : viewport.minX))
            #expect(pinch.completedProgress == 1)
        }
    }
}
