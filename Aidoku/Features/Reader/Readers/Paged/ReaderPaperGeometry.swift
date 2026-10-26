import UIKit

extension ReaderBookSpineView {
    enum BindingEdge { case none, left, right }

    /// Reader paper has square fore-edges; the binding curve is independent of
    /// the rounded shape used by a closed library cover.
    static func cornerRadius(in rect: CGRect) -> CGFloat {
        guard rect.size.width > 0, rect.size.height > 0, !rect.isInfinite, !rect.isNull,
              [rect.width, rect.height].allSatisfy(\.isFinite) else { return 0 }
        #if SUMI
        return 0
        #else
        return min(28, rect.height * 0.055, rect.width * 0.16)
        #endif
    }

    static func bindingCurve(in rect: CGRect) -> (clearance: CGFloat, flare: CGFloat, length: CGFloat) {
        #if SUMI
        // An 8-point inner corner, independent of the viewport's overall size.
        // Only tiny previews reduce it further to keep the curve within paper.
        let radius = min(8, max(0, rect.width / 2), max(0, rect.height / 2))
        return (min(0.65, max(0, rect.width) * 0.005), radius, radius)
        #else
        return (min(0.65, rect.width * 0.005), min(24, rect.width * 0.075, rect.height * 0.04),
                min(64, rect.height * 0.13))
        #endif
    }

    static func pagePath(in rect: CGRect, bindingEdge: BindingEdge = .none, radius: CGFloat? = nil) -> CGPath {
        guard rect.size.width > 0, rect.size.height > 0, !rect.isInfinite, !rect.isNull,
              [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) else {
            return CGPath(rect: .zero, transform: nil)
        }
        #if SUMI
        if bindingEdge != .none {
            // Only the bound edge turns into the gutter. The fore-edge stays
            // square, including in the snapshots used by the moving mesh.
            let curve = bindingCurve(in: rect)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX + curve.flare, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + curve.flare, y: rect.maxY))
            path.addCurve(to: CGPoint(x: rect.minX + curve.clearance, y: rect.maxY - curve.length),
                          control1: CGPoint(x: rect.minX + curve.clearance, y: rect.maxY),
                          control2: CGPoint(x: rect.minX + curve.clearance, y: rect.maxY - curve.length * 0.42))
            path.addLine(to: CGPoint(x: rect.minX + curve.clearance, y: rect.minY + curve.length))
            path.addCurve(to: CGPoint(x: rect.minX + curve.flare, y: rect.minY),
                          control1: CGPoint(x: rect.minX + curve.clearance, y: rect.minY + curve.length * 0.42),
                          control2: CGPoint(x: rect.minX + curve.clearance, y: rect.minY))
            path.closeSubpath()
            if bindingEdge == .left { return path }
            var mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0)
            return path.copy(using: &mirror) ?? path
        }
        #endif
        var paper = rect
        // The gutter is empty space between paper surfaces, never a stroke.
        let clearance = min(0.75, rect.width * 0.005)
        if bindingEdge == .left { paper.origin.x += clearance; paper.size.width -= clearance }
        if bindingEdge == .right { paper.size.width -= clearance }
        let requestedRadius = radius.flatMap { $0.isFinite ? max(0, $0) : nil } ?? cornerRadius(in: rect)
        let r = min(requestedRadius, paper.width / 2, paper.height / 2)
        let tangent = r * 0.70
        let path = CGMutablePath()
        path.move(to: CGPoint(x: paper.minX + r, y: paper.minY))
        path.addLine(to: CGPoint(x: paper.maxX - r, y: paper.minY))
        path.addCurve(to: CGPoint(x: paper.maxX, y: paper.minY + r),
                      control1: CGPoint(x: paper.maxX - r + tangent, y: paper.minY),
                      control2: CGPoint(x: paper.maxX, y: paper.minY + r - tangent))
        path.addLine(to: CGPoint(x: paper.maxX, y: paper.maxY - r))
        path.addCurve(to: CGPoint(x: paper.maxX - r, y: paper.maxY),
                      control1: CGPoint(x: paper.maxX, y: paper.maxY - r + tangent),
                      control2: CGPoint(x: paper.maxX - r + tangent, y: paper.maxY))
        path.addLine(to: CGPoint(x: paper.minX + r, y: paper.maxY))
        path.addCurve(to: CGPoint(x: paper.minX, y: paper.maxY - r),
                      control1: CGPoint(x: paper.minX + r - tangent, y: paper.maxY),
                      control2: CGPoint(x: paper.minX, y: paper.maxY - r + tangent))
        path.addLine(to: CGPoint(x: paper.minX, y: paper.minY + r))
        path.addCurve(to: CGPoint(x: paper.minX + r, y: paper.minY),
                      control1: CGPoint(x: paper.minX, y: paper.minY + r - tangent),
                      control2: CGPoint(x: paper.minX + r - tangent, y: paper.minY))
        path.closeSubpath()
        return path
    }
}
