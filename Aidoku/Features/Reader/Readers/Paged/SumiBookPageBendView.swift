#if SUMI
import UIKit

/// A bounded, cached paper mesh over the native page surface. Its 32 strips are
/// baked once as affine triangles, making the live print and the curl's normal
/// layer snapshot identical. No images are processed during an animation tick.
final class SumiBookPageBendView: UIView {
    private struct SnapshotKey: Equatable {
        let image: ObjectIdentifier
        let size: CGSize
        let imageFrame: CGRect
        let edge: ReaderBookSpineView.BindingEdge
        let scale: CGFloat
        let appearance: UIUserInterfaceStyle
        let paperTexture: Bool
        let textureStrength: String
    }

    private let paper = CALayer()
    private weak var hiddenNativeImage: UIView?
    private var snapshotKey: SnapshotKey?
    private(set) var snapshotCount = 0
    var isPrepared: Bool { snapshotKey != nil }

    init() {
        super.init(frame: .zero)
        accessibilityIdentifier = "Sumi.Reader.SettledPaperBend"
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
        isOpaque = false
        isHidden = true
        paper.contentsGravity = .resize
        paper.minificationFilter = .linear
        paper.magnificationFilter = .linear
        layer.addSublayer(paper)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(image: UIImage?, animated: Bool, ready: Bool, edge: ReaderBookSpineView.BindingEdge,
                source: UIView, nativeImage: UIView, imageFrame: CGRect) {
        guard edge != .none, ready, !animated, let image, image.images == nil, image.cgImage != nil,
              source.bounds.width > 1, source.bounds.height > 1,
              [source.bounds.width, source.bounds.height].allSatisfy(\.isFinite) else {
            reset()
            return
        }
        // Cap the extra texture at 1.4M pixels per leaf, including on a 3x
        // display. The finished mesh retains one bitmap, never sliced copies.
        let scale = min(2, max(1, source.traitCollection.displayScale),
            sqrt(1_400_000 / (source.bounds.width * source.bounds.height)))
        let key = SnapshotKey(image: ObjectIdentifier(image), size: source.bounds.size, imageFrame: imageFrame,
            edge: edge, scale: scale, appearance: source.traitCollection.userInterfaceStyle,
            paperTexture: AppSettings.reader.paperTexture.get(), textureStrength: AppSettings.reader.paperTextureStrength.get().rawValue)
        frame = source.bounds
        if snapshotKey == key, hiddenNativeImage === nativeImage {
            if isHidden { isHidden = false }
            return
        }

        // Capture only the unbent native surface. A reused leaf must not feed
        // its old mesh back into the next snapshot and compound the curvature.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        isHidden = true
        hiddenNativeImage?.isHidden = false
        let nativeWasHidden = nativeImage.isHidden
        nativeImage.isHidden = false
        let nativeMask = source.layer.mask
        source.layer.mask = nil
        let bindingLights = (source.layer.sublayers ?? []).filter { $0.name == ReaderBookSpineView.bindingLightingName }
        let lightVisibility = bindingLights.map(\.isHidden)
        bindingLights.forEach { $0.isHidden = true }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let snapshot = UIGraphicsImageRenderer(size: source.bounds.size, format: format).image { context in
            source.layer.render(in: context.cgContext)
        }
        source.layer.mask = nativeMask
        for (light, wasHidden) in zip(bindingLights, lightVisibility) { light.isHidden = wasHidden }
        nativeImage.isHidden = nativeWasHidden
        let bent = Self.bake(snapshot, in: bounds, edge: edge, scale: scale)
        guard let bitmap = bent.cgImage else {
            CATransaction.commit()
            reset()
            return
        }
        paper.frame = bounds
        paper.contents = bitmap
        paper.contentsScale = scale
        snapshotKey = key
        snapshotCount += 1
        nativeImage.isHidden = true
        hiddenNativeImage = nativeImage
        isHidden = false
        CATransaction.commit()
    }

    private static func bake(_ image: UIImage, in bounds: CGRect,
                             edge: ReaderBookSpineView.BindingEdge, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { output in
            let context = output.cgContext
            context.interpolationQuality = .high
            // Shared triangle boundaries partition the print exactly. Turning
            // clip antialiasing off prevents a pale seam between adjacent faces.
            context.setShouldAntialias(false)
            context.setAllowsAntialiasing(false)
            for index in 0..<SumiBookPageBendGeometry.stripCount {
                let range = SumiBookPageBendGeometry.textureRange(strip: index, edge: edge)
                let left = range.lowerBound * bounds.width
                let right = range.upperBound * bounds.width
                let corners = [CGPoint(x: left, y: 0), CGPoint(x: right, y: 0),
                    CGPoint(x: right, y: bounds.height), CGPoint(x: left, y: bounds.height)]
                for indices in [[0, 1, 3], [1, 2, 3]] {
                    let original = indices.map { corners[$0] }
                    let projected = original.map { SumiBookPageBendGeometry.point($0, in: bounds, edge: edge) }
                    let clip = CGMutablePath()
                    clip.addLines(between: projected)
                    clip.closeSubpath()
                    context.saveGState()
                    context.addPath(clip)
                    context.clip()
                    context.concatenate(SumiBookPageBendGeometry.affine(from: original, to: projected))
                    image.draw(in: CGRect(origin: .zero, size: bounds.size))
                    context.restoreGState()
                }
            }
        }
    }

    /// Portrait, loading, animated artwork, and detached leaves use the native
    /// renderer again and release the extra texture immediately.
    func reset() {
        guard snapshotKey != nil || hiddenNativeImage != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        isHidden = true
        hiddenNativeImage?.isHidden = false
        hiddenNativeImage = nil
        snapshotKey = nil
        paper.contents = nil
        CATransaction.commit()
    }
}
#endif
