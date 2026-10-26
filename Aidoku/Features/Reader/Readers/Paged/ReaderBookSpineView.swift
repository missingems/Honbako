import UIKit

/// The unlit space below curved paper edges. Sumi keeps this underneath the
/// leaves, so each leaf's binding silhouette can curl over it without a seam
/// painted across the moving paper.
final class ReaderBookSpineView: UIView {
    #if SUMI
    static let bindingLightingName = "sumi.reader.binding-lighting"

    /// Both paper shoulders use the same illumination, mirrored in geometry
    /// rather than relying on layer start/end direction to reverse the stops.
    static func updateBindingLighting(_ lighting: CALayer, in rect: CGRect, edge: BindingEdge) {
        let gradient: CAGradientLayer
        if let existing = lighting.sublayers?.first as? CAGradientLayer { gradient = existing }
        else {
            gradient = CAGradientLayer()
            gradient.colors = [UIColor.black.withAlphaComponent(0.24).cgColor,
                               UIColor.black.withAlphaComponent(0.10).cgColor,
                               UIColor.black.withAlphaComponent(0.025).cgColor, UIColor.clear.cgColor]
            gradient.locations = [0, 0.18, 0.58, 1]
            lighting.addSublayer(gradient)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lighting.frame = rect
        let width = min(72, rect.width * 0.16)
        gradient.frame = CGRect(x: edge == .left ? 0 : rect.width - width,
                                y: 0, width: width, height: rect.height)
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.transform = edge == .left ? CATransform3DIdentity : CATransform3DMakeScale(-1, 1, 1)
        CATransaction.commit()
    }

    /// Dynamic shadows land on paper, never on the unlit cleft itself. Keeping
    /// its material independent prevents the spine darkening at touch-down.
    static func receivingPaperPath(in rect: CGRect, paired: Bool) -> CGPath {
        guard paired else { return pagePath(in: rect) }
        let half = rect.width / 2
        let path = CGMutablePath()
        path.addPath(pagePath(in: CGRect(x: rect.minX, y: rect.minY, width: half, height: rect.height), bindingEdge: .right))
        path.addPath(pagePath(in: CGRect(x: rect.midX, y: rect.minY, width: half, height: rect.height), bindingEdge: .left))
        return path
    }

    static func removeBindingLighting(from layer: CALayer) {
        layer.sublayers?.filter { $0.name == bindingLightingName }.forEach { $0.removeFromSuperlayer() }
    }
    #endif
    private let gutter = CAShapeLayer()
    private let paperEdges = CAShapeLayer()
    private var renderedSize: CGSize = .zero
    private var renderedScale: CGFloat = 0

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityIdentifier = "sumi.reader.spine"
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isOpaque = false
        isHidden = true
        #if SUMI
        gutter.fillColor = UIColor(white: 0.15, alpha: 1).cgColor
        #else
        gutter.fillColor = UIColor.black.cgColor
        #endif
        paperEdges.fillColor = nil
        paperEdges.strokeColor = UIColor(white: 0.96, alpha: 0.6).cgColor
        paperEdges.lineWidth = 0.65
        paperEdges.lineCap = .round
        layer.addSublayer(gutter)
        #if !SUMI
        layer.addSublayer(paperEdges)
        #endif
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = max(1, traitCollection.displayScale)
        guard renderedSize != bounds.size || renderedScale != scale else { return }
        renderedSize = bounds.size
        renderedScale = scale
        let paths = Self.paths(in: bounds)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gutter.contentsScale = scale
        paperEdges.contentsScale = scale
        gutter.frame = bounds
        paperEdges.frame = bounds
        gutter.path = paths.gutter
        paperEdges.path = paths.edges
        CATransaction.commit()
    }

    func update(pageFrames: [CGRect], enabled: Bool) {
        guard enabled, let frame = Self.frame(between: pageFrames) else {
            if !isHidden { isHidden = true }
            if self.frame != .zero { self.frame = .zero }
            return
        }
        if isHidden { isHidden = false }
        if self.frame != frame { self.frame = frame }
    }

    static func frame(between pageFrames: [CGRect]) -> CGRect? {
        guard pageFrames.count == 2,
              pageFrames.allSatisfy({ !$0.isEmpty && !$0.isNull && !$0.isInfinite &&
                  [$0.minX, $0.minY, $0.width, $0.height].allSatisfy(\.isFinite) }) else { return nil }
        let pages = pageFrames.sorted { $0.midX < $1.midX }
        let top = max(pages[0].minY, pages[1].minY)
        let bottom = min(pages[0].maxY, pages[1].maxY)
        guard bottom > top else { return nil }
        let seam = (pages[0].maxX + pages[1].minX) / 2
        #if SUMI
        let width = 2 * bindingCurve(in: CGRect(x: 0, y: 0, width: min(pages[0].width, pages[1].width),
                                               height: bottom - top)).flare
        #else
        let width = min(48, min(pages[0].width, pages[1].width) * 0.3,
                        max(14, pages[0].union(pages[1]).width * 0.05))
        #endif
        return CGRect(x: seam - width / 2, y: top, width: width, height: bottom - top)
    }

    private static func paths(in rect: CGRect) -> (gutter: CGPath, edges: CGPath) {
        #if SUMI
        // Paper masks reveal only the curved cleft. This underlay has no edge
        // stroke and never sits above either the settled or turning leaf.
        return (CGPath(rect: rect, transform: nil), CGMutablePath())
        #else
        let left = UIBezierPath()
        let right = UIBezierPath()
        let center = rect.midX
        let halfCrease = min(1.5, rect.width * 0.12)
        let bend = min(52, rect.height * 0.09)
        left.move(to: CGPoint(x: rect.minX, y: rect.minY))
        left.addCurve(to: CGPoint(x: center - halfCrease, y: rect.minY + bend),
                      controlPoint1: CGPoint(x: center - halfCrease, y: rect.minY),
                      controlPoint2: CGPoint(x: center - halfCrease, y: rect.minY + bend * 0.42))
        left.addLine(to: CGPoint(x: center - halfCrease, y: rect.maxY - bend))
        left.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY),
                      controlPoint1: CGPoint(x: center - halfCrease, y: rect.maxY - bend * 0.42),
                      controlPoint2: CGPoint(x: center - halfCrease, y: rect.maxY))
        right.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        right.addCurve(to: CGPoint(x: center + halfCrease, y: rect.maxY - bend),
                       controlPoint1: CGPoint(x: center + halfCrease, y: rect.maxY),
                       controlPoint2: CGPoint(x: center + halfCrease, y: rect.maxY - bend * 0.42))
        right.addLine(to: CGPoint(x: center + halfCrease, y: rect.minY + bend))
        right.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       controlPoint1: CGPoint(x: center + halfCrease, y: rect.minY + bend * 0.42),
                       controlPoint2: CGPoint(x: center + halfCrease, y: rect.minY))
        let edges = UIBezierPath()
        edges.append(left)
        edges.append(right)
        let gutter = UIBezierPath(cgPath: left.cgPath)
        gutter.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        gutter.addCurve(to: CGPoint(x: center + halfCrease, y: rect.maxY - bend),
                        controlPoint1: CGPoint(x: center + halfCrease, y: rect.maxY),
                        controlPoint2: CGPoint(x: center + halfCrease, y: rect.maxY - bend * 0.42))
        gutter.addLine(to: CGPoint(x: center + halfCrease, y: rect.minY + bend))
        gutter.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                        controlPoint1: CGPoint(x: center + halfCrease, y: rect.minY + bend * 0.42),
                        controlPoint2: CGPoint(x: center + halfCrease, y: rect.minY))
        gutter.close()
        return (gutter.cgPath, edges.cgPath)
        #endif
    }
}
