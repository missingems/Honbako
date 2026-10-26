import UIKit

/// A developable paper cylinder, sampled from its bound edge towards its fore-edge.
/// End points are exact flat leaves. Intermediate points preserve paper length
/// rather than shrinking a screenshot as if it were a rigid card.
struct SumiPageCurlGeometry {
    struct Sample {
        let x: CGFloat
        let elevation: CGFloat
        let angle: CGFloat
    }

    /// A single-page viewport sees a crease travel across the paper. Rotating
    /// the whole leaf hides it outside that viewport for half of a reverse turn.
    /// Flat, circular, and folded sections retain the sheet's original length.
    static func singlePageSample(at fraction: CGFloat, progress: CGFloat, width: CGFloat) -> Sample {
        let u = min(1, max(0, fraction))
        let p = min(1, max(0, progress))
        let distance = u * width
        if p <= 0 { return Sample(x: distance, elevation: 0, angle: 0) }
        if p >= 1 { return Sample(x: -distance, elevation: 0, angle: .pi) }
        let crease = width * (1 - p)
        let radius = width * 0.06 * sin(.pi * p)
        let start = crease - .pi * radius / 2
        let end = crease + .pi * radius / 2
        if distance <= start { return Sample(x: distance, elevation: 0, angle: 0) }
        if distance >= end { return Sample(x: start - (distance - end), elevation: 2 * radius, angle: .pi) }
        let angle = (distance - start) / radius
        return Sample(x: start + radius * sin(angle), elevation: radius * (1 - cos(angle)), angle: angle)
    }

    static func sample(at fraction: CGFloat, progress: CGFloat, width: CGFloat) -> Sample {
        let u = min(1, max(0, fraction))
        let p = min(1, max(0, progress))
        let turn = CGFloat.pi * p
        let bend = 0.68 * sin(turn)
        guard abs(bend) > 0.00001 else {
            return Sample(x: width * u * cos(turn), elevation: 0, angle: turn)
        }
        let startAngle = turn - bend
        let angle = startAngle + 2 * bend * u
        let radius = width / (2 * bend)
        return Sample(x: radius * (sin(angle) - sin(startAngle)),
                      elevation: radius * (cos(startAngle) - cos(angle)),
                      angle: angle)
    }

    static func projected(_ sample: Sample, y: CGFloat, bounds: CGRect,
                          hinge: CGFloat, sign: CGFloat) -> CGPoint {
        let perspective = max(bounds.width * 6.2, 1)
        let scale = perspective / max(1, perspective - sample.elevation)
        return CGPoint(x: hinge + sign * sample.x * scale,
                       y: bounds.midY + (y - bounds.midY) * scale)
    }

    /// The same paper point projected by a light above the left shoulder onto
    /// the flat spread. This is deliberately distinct from the camera's view:
    /// elevated paper casts its shadow beyond its own visible silhouette.
    static func castShadow(_ sample: Sample, y: CGFloat, hinge: CGFloat, sign: CGFloat,
                           lightDirection: CGFloat = 1) -> CGPoint {
        CGPoint(x: hinge + sign * sample.x + sample.elevation * 0.18 * lightDirection,
                y: y + sample.elevation * 0.04)
    }

    /// A lifted sheet darkens gradually at either flat endpoint. A square-root
    /// envelope has an infinite initial slope and makes the gutter appear to pop.
    static func lightingEnvelope(progress: CGFloat) -> CGFloat {
        let lifted = max(0, sin(.pi * min(1, max(0, progress))))
        return lifted * lifted
    }

    /// The curled surface can fold back across its own ground projection. Use
    /// its footprint so overlapping front/back contours cannot cancel out and
    /// leave a bright hole in the middle of the cast shadow.
    static func shadowFootprint(_ points: [CGPoint]) -> CGPath {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard sorted.count > 2 else { return CGMutablePath() }
        func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        var lower: [CGPoint] = []
        var upper: [CGPoint] = []
        for point in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }
        for point in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }
        let hull = lower.dropLast() + upper.dropLast()
        let path = CGMutablePath()
        for (index, point) in hull.enumerated() {
            if index == 0 { path.move(to: point) }
            else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// Homography from a unit rectangle to its projected paper strip. Keeping the
    /// original texture in contentsRect makes Core Animation do the resampling.
    static func transform(topLeft: CGPoint, topRight: CGPoint,
                          bottomRight: CGPoint, bottomLeft: CGPoint) -> CATransform3D {
        let dx1 = topRight.x - bottomRight.x
        let dx2 = bottomLeft.x - bottomRight.x
        let dx3 = topLeft.x - topRight.x + bottomRight.x - bottomLeft.x
        let dy1 = topRight.y - bottomRight.y
        let dy2 = bottomLeft.y - bottomRight.y
        let dy3 = topLeft.y - topRight.y + bottomRight.y - bottomLeft.y
        let denominator = dx1 * dy2 - dx2 * dy1
        var g: CGFloat = 0
        var h: CGFloat = 0
        if abs(denominator) > 0.0000001 {
            g = (dx3 * dy2 - dx2 * dy3) / denominator
            h = (dx1 * dy3 - dx3 * dy1) / denominator
        }
        var result = CATransform3DIdentity
        result.m11 = topRight.x - topLeft.x + g * topRight.x
        result.m12 = topRight.y - topLeft.y + g * topRight.y
        result.m14 = g
        result.m21 = bottomLeft.x - topLeft.x + h * bottomLeft.x
        result.m22 = bottomLeft.y - topLeft.y + h * bottomLeft.y
        result.m24 = h
        result.m41 = topLeft.x
        result.m42 = topLeft.y
        return result
    }
}
