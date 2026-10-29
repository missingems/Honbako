#if SUMI
import UIKit

/// One isometric cone rotated about its binding. Horizontal and vertical paper
/// fibres retain their lengths; no independent rows or displacement kinks.
struct SumiPageCurlDeformation {
    struct Vertex {
        let paper: SumiPageCurlGeometry.Sample
        let y: CGFloat
    }
    let size: CGSize
    var grip: CGPoint
    var verticalBend: CGFloat = 0

    func vertex(x: CGFloat, y: CGFloat, progress: CGFloat) -> Vertex {
        let p = min(1, max(0, progress)), turn = CGFloat.pi * p
        if p <= 0 { return Vertex(paper: .init(x: x, elevation: 0, angle: 0), y: y) }
        if p >= 1 { return Vertex(paper: .init(x: -x, elevation: 0, angle: .pi), y: y) }
        if x == 0 { return Vertex(paper: .init(x: 0, elevation: 0, angle: turn), y: y) }
        let height = max(1, size.height), top = grip.y <= height / 2
        let localY = top ? y : height - y
        let centre = 1 - abs(2 * grip.y / height - 1)
        let apex = height * (0.2 + 0.85 * centre * centre)
        let inward = verticalBend / height * (top ? 1 : -1)
        let strength = 0.62 + 0.28 * CGFloat(tanh(Double(inward * 3)))
        let angle = CGFloat.pi / 2 - strength * sin(turn)
        let sine = sin(angle), cosine = cos(angle)
        let distanceY = localY + apex, radius = hypot(x, distanceY)
        let azimuth = atan2(x, distanceY) / sine, coneRadius = radius * sine
        let foldedX = coneRadius * sin(azimuth)
        let foldedY = radius - coneRadius * sine * (1 - cos(azimuth)) - apex
        let foldedZ = coneRadius * cosine * (1 - cos(azimuth))
        let normalTurn = atan2(cosine * sin(azimuth), sine * sine + cosine * cosine * cos(azimuth))
        return Vertex(paper: .init(x: foldedX * cos(turn) - foldedZ * sin(turn),
            elevation: foldedX * sin(turn) + foldedZ * cos(turn), angle: turn + normalTurn),
            y: top ? foldedY : height - foldedY)
    }

    /// Invert the held point. Vertical pulls change the cone rather than
    /// stretching a texture or imposing separate turn phases on its rows.
    func progress(horizontalTranslation: CGFloat) -> CGFloat {
        guard horizontalTranslation.isFinite else { return 0 }
        if horizontalTranslation >= 0 { return 0 }
        if horizontalTranslation <= -grip.x * 2 { return 1 }
        let target = grip.x + horizontalTranslation
        var lower: CGFloat = 0, upper: CGFloat = 1
        for _ in 0..<18 {
            let p = (lower + upper) / 2
            if vertex(x: grip.x, y: grip.y, progress: p).paper.x > target { lower = p }
            else { upper = p }
        }
        return (lower + upper) / 2
    }
}
#endif
