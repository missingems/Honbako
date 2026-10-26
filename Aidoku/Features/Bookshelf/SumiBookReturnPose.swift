#if SUMI
import CoreGraphics
/// Close the cover while travelling directly to the collection slot. A partial
/// opening can start from its exact visible paper without visiting a hover pose.
struct SumiBookReturnPose {
    let openness: CGFloat
    let sourceFrame: CGRect
    let gridDimming: CGFloat
    private let progress: CGFloat

    init(progress: CGFloat, origin: CGRect, initialOpenness: CGFloat = 1) {
        self.progress = min(1, max(0, progress))
        openness = min(1, max(0, initialOpenness)) * self.progress
        sourceFrame = origin
        gridDimming = 0.68 * self.progress
    }

    func paperFrame(in viewport: CGRect, paired: Bool, startingAt initialFrame: CGRect? = nil) -> CGRect {
        guard let initialFrame else {
            return SumiBookMotion.paperFrame(source: sourceFrame, destination: viewport, paired: paired, progress: progress)
        }
        let closed = SumiBookMotion.paperFrame(source: sourceFrame, destination: viewport, paired: paired, progress: 0)
        return interpolatedFrame(startingAt: initialFrame, endingAt: closed)
    }

    func coverFrame(startingAt initialFrame: CGRect) -> CGRect {
        interpolatedFrame(startingAt: initialFrame, endingAt: sourceFrame)
    }

    private func interpolatedFrame(startingAt initial: CGRect, endingAt destination: CGRect) -> CGRect {
        let width = SumiBookMotion.pointsPerUnit(sourceHeight: destination.width,
            destinationHeight: initial.width, progress: progress)
        let height = SumiBookMotion.pointsPerUnit(sourceHeight: destination.height,
            destinationHeight: initial.height, progress: progress)
        let center = CGPoint(x: destination.midX + (initial.midX - destination.midX) * progress,
                             y: destination.midY + (initial.midY - destination.midY) * progress)
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }
}
#endif
