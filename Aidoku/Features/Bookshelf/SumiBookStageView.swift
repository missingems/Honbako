#if SUMI
import QuartzCore
import UIKit

/// Three image layers open the original cover around its left binding.
/// Core Animation composites the print directly: no shader, sheen or lighting.
final class SumiBookStageView: UIView {
    private let rightPage = CALayer()
    private let hinge = CATransformLayer()
    private let front = CALayer()
    private let back = CALayer()
    private let paired: Bool
    private(set) var draws = 0
    private(set) var completedFrames = 0
    private(set) var completedProgress: CGFloat?
    private(set) var completedSourceFrame: CGRect?
    private var visibleBookFrame = CGRect.zero

    init(frame: CGRect, cover: UIImage?, spread: UIImage, paired: Bool, closedPose _: SumiGridBookPose? = nil) throws {
        self.paired = paired
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = true
        rightPage.contents = Self.upright(spread).cgImage
        rightPage.contentsRect = paired ? CGRect(x: 0.5, y: 0, width: 0.5, height: 1) : CGRect(x: 0, y: 0, width: 1, height: 1)
        rightPage.backgroundColor = UIColor.white.cgColor
        front.contents = Self.upright(cover ?? spread).cgImage
        front.backgroundColor = UIColor.white.cgColor
        front.isDoubleSided = false
        front.zPosition = 0.01
        if paired {
            back.contents = rightPage.contents
            back.contentsRect = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        }
        back.backgroundColor = UIColor.white.cgColor
        back.isDoubleSided = false
        back.transform = CATransform3DMakeRotation(.pi, 0, 1, 0)
        back.zPosition = -0.01
        [rightPage, front, back].forEach {
            $0.contentsGravity = .resize
            $0.minificationFilter = .trilinear
            $0.magnificationFilter = .linear
            $0.allowsEdgeAntialiasing = true
        }
        // Page snapshots already match their viewport. A provider's cover can
        // have any aspect ratio, so crop its print proportionally at the hinge.
        front.contentsGravity = .resizeAspectFill
        front.masksToBounds = true
        hinge.anchorPoint = CGPoint(x: 0, y: 0.5)
        layer.addSublayer(rightPage)
        layer.addSublayer(hinge)
        hinge.addSublayer(front)
        hinge.addSublayer(back)
        accessibilityIdentifier = "Sumi.Book.OpeningStage"
        isAccessibilityElement = true
        accessibilityLabel = "Opening book"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func draw(progress: CGFloat, source: CGRect, paperFrame: CGRect? = nil, deltaTime _: TimeInterval) -> Bool {
        guard bounds.width > 1, bounds.height > 1 else { return false }
        let value = min(1, max(0, progress))
        let frame = paperFrame ?? SumiBookMotion.paperFrame(source: source, destination: bounds,
                                                          paired: paired, progress: value)
        let leaf = CGRect(x: paired ? frame.midX : frame.minX, y: frame.minY,
                          width: frame.width / (paired ? 2 : 1), height: frame.height)
        let projectedWidth = leaf.width * cos(.pi * value)
        let turning = CGRect(x: min(leaf.minX, leaf.minX + projectedWidth), y: leaf.minY,
                             width: abs(projectedWidth), height: leaf.height)
        visibleBookFrame = leaf.union(turning)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rightPage.frame = leaf
        hinge.bounds = CGRect(origin: .zero, size: leaf.size)
        hinge.position = CGPoint(x: leaf.minX, y: leaf.midY)
        front.bounds = hinge.bounds
        front.position = CGPoint(x: leaf.width / 2, y: leaf.height / 2)
        back.bounds = hinge.bounds
        back.position = front.position
        hinge.transform = CATransform3DMakeRotation(-.pi * value, 0, 1, 0)
        CATransaction.commit()
        draws += 1
        completedFrames += 1
        completedProgress = value
        completedSourceFrame = source
        accessibilityValue = "\(Int(value * 100)) percent"
        return true
    }

    func containsBook(at point: CGPoint) -> Bool { visibleBookFrame.contains(point) }

    private static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
#endif
