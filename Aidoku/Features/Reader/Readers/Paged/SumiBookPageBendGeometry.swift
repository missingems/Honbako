#if SUMI
import UIKit

/// A shallow, settled binding shoulder. Only the inner band changes shape;
/// artwork across the rest of the leaf retains its original size and position.
enum SumiBookPageBendGeometry {
    static let stripCount = 32

    static func bindingWidth(in bounds: CGRect) -> CGFloat {
        min(96, max(0, bounds.width) * 0.28)
    }

    static func point(_ point: CGPoint, in bounds: CGRect, edge: ReaderBookSpineView.BindingEdge) -> CGPoint {
        guard edge != .none, bounds.width > 0, bounds.height > 0,
              [bounds.width, bounds.height, point.x, point.y].allSatisfy(\.isFinite) else { return point }
        let band = bindingWidth(in: bounds)
        guard band > 0 else { return point }
        let distance = edge == .left ? point.x - bounds.minX : bounds.maxX - point.x
        guard distance >= 0, distance < band else { return point }
        let t = distance / band
        let shoulder = pow(1 - t, 3)
        // The source texture compresses toward the binding, then smoothly
        // rejoins the flat page. Its derivative remains positive everywhere.
        let projectedDistance = distance - band * 0.75 * t * shoulder
        let inset = min(14, bounds.height * 0.018) * shoulder
        return CGPoint(x: edge == .left ? bounds.minX + projectedDistance : bounds.maxX - projectedDistance,
            y: bounds.midY + (point.y - bounds.midY) * (1 - 2 * inset / bounds.height))
    }

    /// Concentrate samples near the spine without increasing the layer count.
    static func textureRange(strip: Int, edge: ReaderBookSpineView.BindingEdge) -> ClosedRange<CGFloat> {
        let first = pow(CGFloat(strip) / CGFloat(stripCount), 2)
        let last = pow(CGFloat(strip + 1) / CGFloat(stripCount), 2)
        return edge == .right ? (1 - last)...(1 - first) : first...last
    }

    /// Map one source triangle onto three projected paper points. Unlike a
    /// projective layer transform, this is also captured by layer.render(in:).
    static func affine(from source: [CGPoint], to target: [CGPoint]) -> CGAffineTransform {
        guard source.count == 3, target.count == 3 else { return .identity }
        let first = CGPoint(x: source[1].x - source[0].x, y: source[1].y - source[0].y)
        let second = CGPoint(x: source[2].x - source[0].x, y: source[2].y - source[0].y)
        let determinant = first.x * second.y - first.y * second.x
        guard abs(determinant) > 0.000001 else { return .identity }
        let outputFirst = CGPoint(x: target[1].x - target[0].x, y: target[1].y - target[0].y)
        let outputSecond = CGPoint(x: target[2].x - target[0].x, y: target[2].y - target[0].y)
        let a = (outputFirst.x * second.y - outputSecond.x * first.y) / determinant
        let c = (outputSecond.x * first.x - outputFirst.x * second.x) / determinant
        let b = (outputFirst.y * second.y - outputSecond.y * first.y) / determinant
        let d = (outputSecond.y * first.x - outputFirst.y * second.x) / determinant
        return CGAffineTransform(a: a, b: b, c: c, d: d,
            tx: target[0].x - a * source[0].x - c * source[0].y,
            ty: target[0].y - b * source[0].x - d * source[0].y)
    }
}
#endif
