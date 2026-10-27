#if SUMI
import UIKit

/// Four flat margin bands behind the unchanged page bitmap. Paper texture stays
/// on the image; it cannot wash a sampled black border into a gray letterbox.
final class SumiPageEdgeBackgroundView: UIView {
    struct Regions: Equatable {
        let top: CGRect
        let leading: CGRect
        let trailing: CGRect
        let bottom: CGRect
    }

    private let top = CALayer()
    private let leading = CALayer()
    private let trailing = CALayer()
    private let bottom = CALayer()
    private var sampling: Task<Void, Never>?
    private var generation = 0
    private var identity: String?
    private var imageFrame = CGRect.zero
    private(set) var colors: SumiPageEdgeColors?
    var isReady: Bool { sampling == nil }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
        clipsToBounds = true
        [top, leading, trailing, bottom].forEach { layer.addSublayer($0) }
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { sampling?.cancel() }

    func update(image: UIImage?, crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) {
        guard let image, let bitmap = image.cgImage ?? image.images?.first?.cgImage else {
            clear()
            return
        }
        guard [crop.minX, crop.minY, crop.width, crop.height].allSatisfy(\.isFinite) else { clear(); return }
        let crop = crop.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !crop.isNull, !crop.isEmpty else { clear(); return }
        let next = SumiPageEdgeColors.identity(image: bitmap, orientation: image.imageOrientation, crop: crop)
        guard identity != next else { return }
        sampling?.cancel()
        generation += 1
        let request = generation
        identity = next
        let orientation = image.imageOrientation
        sampling = Task { [weak self] in
            let detector = Task.detached(priority: .utility) {
                SumiPageEdgeColors.sample(image: bitmap, orientation: orientation, crop: crop)
            }
            let result = await withTaskCancellationHandler {
                await detector.value
            } onCancel: { detector.cancel() }
            guard let self, !Task.isCancelled, generation == request else { return }
            sampling = nil
            apply(result)
        }
    }

    func layout(imageFrame: CGRect) {
        self.imageFrame = imageFrame
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let regions = Self.regions(in: bounds, imageFrame: imageFrame)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (band, frame) in zip([top, leading, trailing, bottom],
                                 [regions.top, regions.leading, regions.trailing, regions.bottom]) {
            band.frame = frame
            band.isHidden = frame.isEmpty || colors == nil
        }
        CATransaction.commit()
    }

    static func regions(in bounds: CGRect, imageFrame: CGRect) -> Regions {
        let image = imageFrame.intersection(bounds)
        guard !bounds.isEmpty, !image.isEmpty, !image.isNull else {
            return Regions(top: .zero, leading: .zero, trailing: .zero, bottom: .zero)
        }
        return Regions(
            top: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(0, image.minY - bounds.minY)),
            leading: CGRect(x: bounds.minX, y: image.minY, width: max(0, image.minX - bounds.minX), height: image.height),
            trailing: CGRect(x: image.maxX, y: image.minY, width: max(0, bounds.maxX - image.maxX), height: image.height),
            bottom: CGRect(x: bounds.minX, y: image.maxY, width: bounds.width, height: max(0, bounds.maxY - image.maxY)))
    }

    private func clear() {
        guard identity != nil || colors != nil || sampling != nil else { return }
        generation += 1
        sampling?.cancel(); sampling = nil
        identity = nil
        colors = nil
        alpha = 0
        setNeedsLayout()
    }

    private func apply(_ colors: SumiPageEdgeColors?) {
        self.colors = colors
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (band, color) in zip([top, leading, trailing, bottom], [colors?.top, colors?.leading, colors?.trailing, colors?.bottom]) {
            band.backgroundColor = color?.uiColor.cgColor
        }
        CATransaction.commit()
        setNeedsLayout()
        // A margin is an extension of its bitmap edge, not another paper
        // surface to reveal. Fading black over the white loading surface turns
        // it gray, and a page-turn/rotation snapshot can retain that blended
        // color. The image keeps its own loading fade; its edge colors publish
        // atomically and fully opaque before the page reports readiness.
        UIView.performWithoutAnimation { alpha = colors == nil ? 0 : 1 }
    }
}
#endif
