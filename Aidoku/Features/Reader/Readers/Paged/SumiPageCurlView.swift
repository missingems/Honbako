#if SUMI
import UIKit

/// A single physical leaf: the current front and the next verso share the same
/// moving mesh, including their curved binding edge. There is no fixed gutter
/// drawn above the curl and no texture swap at the middle of the turn.
final class SumiPageCurlView: UIView {
    /// Printed faces are prepared before a scrub's clock starts. One moving
    /// mesh can then reuse its layers for every adjacent physical leaf.
    struct Artwork {
        fileprivate let front: UIImage
        fileprivate let back: UIImage
        fileprivate let stationary: UIImage?
        fileprivate let revealed: UIImage
        fileprivate let paired: Bool
        fileprivate let rightToLeft: Bool
    }

    private struct Strip {
        let front: CALayer
        let back: CALayer
        let shade: CALayer
        let lower: CGFloat
        let upper: CGFloat
    }

    private var strips: [Strip] = []
    private let paper = CALayer()
    private let stationary = CALayer()
    private let revealed = CALayer()
    private let castShadow = CALayer()
    private let contactShadow = CALayer()
    private var shadowOutline: [CGPoint] = []
    private let paired: Bool
    let rightToLeft: Bool
    private var returnsPreviousLeaf: Bool { !paired && !rightToLeft }
    private let leafWidth: CGFloat
    private let hinge: CGFloat
    private let sign: CGFloat

    convenience init(frame: CGRect, oldImages: [UIImage], newImages: [UIImage], rightToLeft: Bool) {
        self.init(frame: frame, artwork: Self.prepareArtwork(oldImages: oldImages, newImages: newImages, rightToLeft: rightToLeft))
    }

    init(frame: CGRect, artwork: Artwork) {
        paired = artwork.paired
        rightToLeft = artwork.rightToLeft
        leafWidth = paired ? frame.width / 2 : frame.width
        // A single visible page remains bound on the left in both directions.
        // Going back returns the previous leaf; it does not peel the current
        // page off a new binding on the opposite edge.
        hinge = paired ? frame.width / 2 : 0
        sign = paired && !rightToLeft ? -1 : 1
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = SumiPaperSurface.backgroundColor
        clipsToBounds = true
        if paired {
            let spine = ReaderBookSpineView()
            addSubview(spine)
            spine.update(pageFrames: [CGRect(x: 0, y: 0, width: leafWidth, height: bounds.height),
                                      CGRect(x: leafWidth, y: 0, width: leafWidth, height: bounds.height)], enabled: true)
            spine.layoutIfNeeded()
        }
        stationary.name = "sumi.reader.stationary-paper"
        revealed.name = "sumi.reader.revealed-paper"
        layer.addSublayer(stationary)
        layer.addSublayer(revealed)
        for shadow in [castShadow, contactShadow] {
            shadow.frame = bounds
            shadow.shadowColor = UIColor.black.cgColor
            shadow.shadowOffset = .zero
            let receivingPaper = CAShapeLayer()
            receivingPaper.frame = bounds
            receivingPaper.path = ReaderBookSpineView.receivingPaperPath(in: bounds, paired: paired)
            shadow.mask = receivingPaper
            layer.addSublayer(shadow)
        }
        castShadow.name = "sumi.reader.cast-shadow"
        contactShadow.name = "sumi.reader.binding-contact-shadow"
        paper.name = "sumi.reader.moving-paper"
        layer.addSublayer(paper)
        shadowOutline = Self.outline(in: CGRect(x: 0, y: 0, width: leafWidth, height: bounds.height),
                                     bindingEdge: paired ? .left : .none)

        let orientedFront = artwork.front
        let orientedBack = artwork.back
        let count = 56
        for index in 0..<count {
            let lower = CGFloat(index) / CGFloat(count)
            let upper = CGFloat(index + 1) / CGFloat(count)
            let front = makeFace(image: orientedFront, lower: lower, upper: upper)
            let back = makeFace(image: orientedBack, lower: lower, upper: upper)
            let shade = CALayer()
            shade.anchorPoint = .zero
            shade.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
            shade.backgroundColor = UIColor.black.cgColor
            shade.mask = makeFace(image: orientedFront, lower: lower, upper: upper)
            paper.addSublayer(front)
            paper.addSublayer(back)
            paper.addSublayer(shade)
            strips.append(Strip(front: front, back: back, shade: shade, lower: lower, upper: upper))
        }
        updateReceivingArtwork(artwork)
        update(progress: 0)
    }

    /// UIImage processing belongs to preparation, never to a timed leaf boundary.
    static func prepareArtwork(oldImages: [UIImage], newImages: [UIImage], rightToLeft: Bool) -> Artwork {
        let paired = oldImages.count == 2 && newImages.count == 2
        let returning = !paired && !rightToLeft
        let active = returning ? newImages[0] : oldImages[paired ? (rightToLeft ? 1 : 0) : 0]
        let back: UIImage
        let stationary: UIImage?
        let revealed: UIImage
        if paired {
            back = mirrored(newImages[rightToLeft ? 0 : 1])
            stationary = oldImages[rightToLeft ? 0 : 1]
            revealed = newImages[rightToLeft ? 1 : 0]
        } else {
            back = reversePaper(active)
            stationary = nil
            revealed = returning ? oldImages[0] : newImages[0]
        }
        let mirrorsPrint = paired && !rightToLeft
        return Artwork(front: mirrorsPrint ? mirrored(active) : active,
                       back: mirrorsPrint ? mirrored(back) : back,
                       stationary: stationary, revealed: revealed,
                       paired: paired, rightToLeft: rightToLeft)
    }

    @discardableResult
    func replaceArtwork(_ artwork: Artwork) -> Bool {
        guard artwork.paired == paired, artwork.rightToLeft == rightToLeft else { return false }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateReceivingArtwork(artwork)
        for strip in strips {
            strip.front.contents = artwork.front.cgImage
            strip.back.contents = artwork.back.cgImage
            strip.shade.mask?.contents = artwork.front.cgImage
        }
        update(progress: 0)
        CATransaction.commit()
        return true
    }

    private func updateReceivingArtwork(_ artwork: Artwork) {
        stationary.contents = artwork.stationary?.cgImage
        revealed.contents = artwork.revealed.cgImage
        stationary.contentsGravity = .resize
        revealed.contentsGravity = .resize
        if paired {
            stationary.frame = CGRect(x: rightToLeft ? 0 : leafWidth, y: 0, width: leafWidth, height: bounds.height)
            revealed.frame = CGRect(x: rightToLeft ? leafWidth : 0, y: 0, width: leafWidth, height: bounds.height)
        } else {
            stationary.frame = .zero
            revealed.frame = bounds
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func makeFace(image: UIImage, lower: CGFloat, upper: CGFloat) -> CALayer {
        let face = CALayer()
        face.anchorPoint = .zero
        face.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        face.contents = image.cgImage
        face.contentsRect = CGRect(x: lower, y: 0, width: upper - lower, height: 1)
        face.contentsGravity = .resize
        face.minificationFilter = .linear
        face.magnificationFilter = .linear
        face.allowsEdgeAntialiasing = true
        face.edgeAntialiasingMask = [.layerTopEdge, .layerBottomEdge]
        return face
    }

    func update(progress: CGFloat) {
        let travel = min(1, max(0, progress))
        // Reverse is the exact same sheet motion played back toward its resting
        // position. This also keeps the cast shadow on the correct receiving page.
        let p = returnsPreviousLeaf ? 1 - travel : travel
        // Move the camera back rather than flattening the cylinder itself;
        // the mesh retains its true arc length throughout the turn.
        func projected(_ sample: SumiPageCurlGeometry.Sample, y: CGFloat) -> CGPoint {
            SumiPageCurlGeometry.projected(sample, y: y, bounds: bounds, hinge: hinge, sign: sign)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for strip in strips {
            let a = sample(at: strip.lower, progress: p)
            let b = sample(at: strip.upper, progress: p)
            let topA = projected(a, y: 0)
            let topB = projected(b, y: 0)
            let bottomA = projected(a, y: bounds.height)
            let bottomB = projected(b, y: bounds.height)
            let transform = SumiPageCurlGeometry.transform(topLeft: topA, topRight: topB,
                                                         bottomRight: bottomB, bottomLeft: bottomA)
            let frontFacing = cos((a.angle + b.angle) / 2) >= 0
            strip.front.transform = transform
            strip.back.transform = transform
            strip.shade.transform = transform
            strip.front.isHidden = !frontFacing
            strip.back.isHidden = frontFacing
            strip.shade.mask?.contents = frontFacing ? strip.front.contents : strip.back.contents
            // Lighting follows the paper's normal, rather than painting an
            // artificial border along either the spine or the outer edge.
            strip.shade.opacity = Float(0.075 * SumiPageCurlGeometry.lightingEnvelope(progress: p) * abs(sin((a.angle + b.angle) / 2)))
            let depth = (a.elevation + b.elevation) / 2
            strip.front.zPosition = depth
            strip.back.zPosition = depth
            strip.shade.zPosition = depth + 0.01
        }
        updateCastShadow(progress: p)
        CATransaction.commit()
    }

    private func updateCastShadow(progress: CGFloat) {
        var projectedOutline: [CGPoint] = []
        projectedOutline.reserveCapacity(shadowOutline.count * 2)
        var maximumElevation: CGFloat = 0
        for point in shadowOutline {
            let sample = sample(at: point.x / leafWidth, progress: progress)
            maximumElevation = max(maximumElevation, sample.elevation)
            // A broad overhead light gives the leaf a soft receiving shadow
            // on both shoulders. A fixed rightward ray leaves the left page
            // visually ungrounded while the sheet passes over the centre.
            for direction: CGFloat in [-1, 1] {
                projectedOutline.append(SumiPageCurlGeometry.castShadow(sample, y: point.y,
                    hinge: hinge, sign: sign, lightDirection: direction))
            }
        }
        let lighting = SumiPageCurlGeometry.lightingEnvelope(progress: progress)
        // These layers are below every moving strip. Supplying a geometric
        // shadowPath avoids rasterizing the animated paper mesh at 120 Hz.
        castShadow.shadowPath = SumiPageCurlGeometry.shadowFootprint(projectedOutline)
        castShadow.shadowRadius = min(19, 2 + maximumElevation * 0.045)
        castShadow.shadowOpacity = Float(0.27 * lighting)
        let contact = CGRect(x: hinge - 1.5, y: 0, width: 3, height: bounds.height)
        contactShadow.shadowPath = CGPath(rect: contact, transform: nil)
        contactShadow.shadowRadius = 3
        contactShadow.shadowOpacity = Float(0.10 * lighting)
    }

    private func sample(at fraction: CGFloat, progress: CGFloat) -> SumiPageCurlGeometry.Sample {
        paired
            ? SumiPageCurlGeometry.sample(at: fraction, progress: progress, width: leafWidth)
            : SumiPageCurlGeometry.singlePageSample(at: fraction, progress: progress, width: leafWidth)
    }

    /// Cache a tessellated paper perimeter once. Its binding shoulder uses the
    /// exact settled page path rather than a rectangular shadow approximation.
    private static func outline(in rect: CGRect, bindingEdge: ReaderBookSpineView.BindingEdge) -> [CGPoint] {
        var points: [CGPoint] = []
        var current = CGPoint.zero
        let path = ReaderBookSpineView.pagePath(in: rect, bindingEdge: bindingEdge)
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
                case .moveToPoint:
                    current = element.points[0]
                    points.append(current)
                case .addLineToPoint:
                    let start = current
                    let end = element.points[0]
                    let count = max(1, Int(ceil(abs(end.x - start.x) / max(1, rect.width) * 56)))
                    for step in 1...count {
                        let t = CGFloat(step) / CGFloat(count)
                        points.append(CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
                    }
                    current = end
                case .addCurveToPoint:
                    let start = current
                    let a = element.points[0]
                    let b = element.points[1]
                    let end = element.points[2]
                    for step in 1...12 {
                        let t = CGFloat(step) / 12
                        let inverse = 1 - t
                        points.append(CGPoint(x: inverse * inverse * inverse * start.x + 3 * inverse * inverse * t * a.x + 3 * inverse * t * t * b.x + t * t * t * end.x,
                                              y: inverse * inverse * inverse * start.y + 3 * inverse * inverse * t * a.y + 3 * inverse * t * t * b.y + t * t * t * end.y))
                    }
                    current = end
                case .closeSubpath: break
                case .addQuadCurveToPoint: break // pagePath uses cubic shoulders.
                @unknown default: break
            }
        }
        return points
    }

    private static func mirrored(_ image: UIImage) -> UIImage {
        UIGraphicsImageRenderer(size: image.size, format: image.imageRendererFormat).image { context in
            context.cgContext.translateBy(x: image.size.width, y: 0)
            context.cgContext.scaleBy(x: -1, y: 1)
            image.draw(at: .zero)
        }
    }

    private static func reversePaper(_ image: UIImage) -> UIImage {
        UIGraphicsImageRenderer(size: image.size, format: image.imageRendererFormat).image { context in
            let rect = CGRect(origin: .zero, size: image.size)
            context.cgContext.addPath(ReaderBookSpineView.pagePath(in: rect))
            context.cgContext.clip()
            SumiPaperSurface.backgroundColor.setFill()
            context.fill(rect)
            context.cgContext.translateBy(x: image.size.width, y: 0)
            context.cgContext.scaleBy(x: -1, y: 1)
            image.draw(at: .zero, blendMode: .multiply, alpha: 0.055)
        }
    }
}
#endif
