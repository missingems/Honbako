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

    /// Compact readers keep a thumb-sized pull; regular-width readers give the
    /// larger book room to track the same gesture without racing to its cover.
    static func backSwipeDistance(width: CGFloat, regularWidth: Bool) -> CGFloat {
        regularWidth ? min(420, max(240, width * 0.36)) : min(160, max(100, width * 0.36))
    }

    static func backSwipeProgress(travel: CGFloat, width: CGFloat, regularWidth: Bool) -> CGFloat {
        min(1, max(0, travel / backSwipeDistance(width: width, regularWidth: regularWidth)))
    }

    static func completesBackSwipe(travel: CGFloat, velocity: CGFloat, width: CGFloat, regularWidth: Bool) -> Bool {
        guard travel >= (regularWidth ? 24 : 12) else { return false }
        if velocity < -140 { return false }
        let threshold = regularWidth ? backSwipeDistance(width: width, regularWidth: true) * 0.4
            : min(56, max(32, width * 0.12))
        return travel + max(0, velocity) * 0.12 >= threshold
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
