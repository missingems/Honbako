#if SUMI
import CoreGraphics

enum SumiBookMotion {
    static let response = 0.4
    static let omega = 2 * Double.pi / response

    static func closeProgress(_ swipe: CGFloat) -> CGFloat {
        min(1, max(0, swipe))
    }

    static func completes(swipe: CGFloat, velocity: CGFloat) -> Bool {
        swipe + velocity * 0.2 >= 0.5
    }

    /// Keep the return gesture within thumb reach even on a wide inner display.
    static func completesBackSwipe(travel: CGFloat, velocity: CGFloat, width: CGFloat) -> Bool {
        guard travel >= 12 else { return false }
        if velocity < -140 { return false }
        let threshold = min(80, max(36, width * 0.18))
        return travel + max(0, velocity) * 0.16 >= threshold
    }

    /// A pinch closes the book itself, never the reader's page scale. A 45%
    /// contraction reaches the collection; opening the fingers retraces it.
    static func pinchProgress(scale: CGFloat) -> CGFloat {
        min(1, max(0, (1 - scale) / 0.45))
    }

    static func pinchVelocity(_ velocity: CGFloat) -> CGFloat { -velocity / 0.45 }

    static func spring(from: CGFloat, to: CGFloat, velocity: CGFloat, time: Double) -> CGFloat {
        let distance = Double(from - to)
        let speed = min(omega * abs(distance), max(-omega * abs(distance), Double(velocity)))
        return to + CGFloat((distance + (speed + omega * distance) * time) * exp(-omega * time))
    }

    static func pointsPerUnit(sourceHeight: CGFloat, destinationHeight: CGFloat, progress: CGFloat) -> CGFloat {
        let start = max(1, sourceHeight)
        return start * pow(max(1, destinationHeight) / start, min(1, max(0, progress)))
    }

    static func coverAngle(progress: CGFloat) -> Float {
        -.pi * Float(min(1, max(0, progress)))
    }

    /// A closed left-bound book occupies the right leaf. Its left edge becomes
    /// the centre binding in a spread, or stays at the leading edge in portrait.
    static func paperFrame(source: CGRect, destination: CGRect, paired: Bool, progress: CGFloat) -> CGRect {
        let value = min(1, max(0, progress))
        let height = pointsPerUnit(sourceHeight: source.height, destinationHeight: destination.height, progress: value)
        let leafAspect = destination.width / max(1, destination.height) / (paired ? 2 : 1)
        let closedScale = source.width / max(1, source.height) / max(0.01, leafAspect)
        let width = destination.width / max(1, destination.height) * height * (closedScale * (1 - value) + value)
        let endBinding = paired ? destination.midX : destination.minX
        let binding = source.minX + (endBinding - source.minX) * value
        let centerY = source.midY + (destination.midY - source.midY) * value
        return CGRect(x: paired ? binding - width / 2 : binding, y: centerY - height / 2, width: width, height: height)
    }
}
#endif
