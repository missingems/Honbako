#if SUMI
import UIKit

/// Page-scoped vector coaching. The bitmap remains untouched, and page/scroll
/// gestures pass through this view to the reader beneath it.
@MainActor
final class HonbakoPageCoachingOverlayView: UIView {
    private typealias Models = HonbakoPageCoachingModels
    private var page: Page?
    private var service = HonbakoPageCoachingService.shared
    private var shapes: [String: CAShapeLayer] = [:]
    private var labels: [String: (container: UIView, title: UILabel)] = [:]
    private var spokenMarks: [UIAccessibilityElement] = []
    private var renderedBounds = CGRect.null
    private var needsAnnotationLayout = true

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        isHidden = true
        accessibilityIdentifier = "Honbako.Reader.PageCoaching.Overlay"
        NotificationCenter.default.addObserver(self, selector: #selector(coachingUpdated),
            name: HonbakoPageCoachingService.updated, object: nil)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitPreferredContentSizeCategory.self]) {
            (view: HonbakoPageCoachingOverlayView, _: UITraitCollection) in
            view.needsAnnotationLayout = true
            view.setNeedsLayout()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    func configure(page: Page?, service: HonbakoPageCoachingService = .shared) {
        guard self.page != page || self.service !== service else { return }
        self.page = page
        self.service = service
        needsAnnotationLayout = true
        // Clear stale marks synchronously when a reused cell changes its page.
        withoutAnimations { renderAnnotationsIfNeeded() }
    }

    /// The reader supplies its actual aspect-fit image frame. Existing image
    /// ancestor transforms then keep every mark attached during zoom/rotation.
    func updateImageFrame(_ frame: CGRect) {
        withoutAnimations {
            if self.frame != frame { self.frame = frame }
            setNeedsLayout()
            layoutIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        withoutAnimations { renderAnnotationsIfNeeded() }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

    override var accessibilityElements: [Any]? {
        get {
            guard !isHidden else { return [] }
            let visible = visibleAnnotationBounds
            return spokenMarks.filter { visible.intersects($0.accessibilityFrameInContainerSpace) }
        }
        set { }
    }

    private var visibleAnnotationBounds: CGRect {
        var visible = bounds
        var ancestor = superview
        while let view = ancestor {
            if view.clipsToBounds || view is UIWindow {
                visible = visible.intersection(convert(view.bounds, from: view))
            }
            ancestor = view.superview
        }
        return visible
    }

    @objc private func coachingUpdated() {
        needsAnnotationLayout = true
        withoutAnimations { renderAnnotationsIfNeeded() }
    }

    private func renderAnnotationsIfNeeded() {
        guard let page, service.isActive, service.matches(page: page), Geometry.valid(bounds) else {
            isHidden = true
            spokenMarks.removeAll()
            shapes.values.forEach { $0.removeFromSuperlayer() }
            labels.values.forEach { $0.container.removeFromSuperview() }
            shapes.removeAll(keepingCapacity: true)
            labels.removeAll(keepingCapacity: true)
            renderedBounds = .null
            return
        }
        isHidden = false
        guard needsAnnotationLayout || renderedBounds != bounds else { return }
        renderedBounds = bounds
        needsAnnotationLayout = false
        var shapeIDs = Set<String>()
        var labelIDs = Set<String>()
        spokenMarks.removeAll(keepingCapacity: true)
        for annotation in service.annotations where HonbakoPageCoachingPolicy.valid(annotation) {
            let color = Self.color(annotation.color).resolvedColor(with: traitCollection)
            switch annotation.type {
            case .label:
                guard let rect = annotation.rect, let frame = Geometry.rect(rect, in: bounds),
                      let text = annotation.text,
                      let contentFrame = Geometry.labelContentFrame(in: CGRect(origin: .zero, size: frame.size)) else { continue }
                let pair = labels[annotation.id] ?? makeLabel()
                labels[annotation.id] = pair
                labelIDs.insert(annotation.id)
                pair.container.frame = frame
                pair.container.layer.borderColor = color.withAlphaComponent(0.75).cgColor
                pair.title.frame = contentFrame
                pair.title.text = text
                pair.title.font = .preferredFont(forTextStyle: .caption1, compatibleWith: traitCollection)
                addSpokenMark(text, frame: frame)
            case .box, .arrow, .stroke:
                guard let path = Geometry.path(for: annotation, in: bounds) else { continue }
                let shape = shapes[annotation.id] ?? makeShape()
                shapes[annotation.id] = shape
                shapeIDs.insert(annotation.id)
                shape.frame = bounds
                shape.bounds = bounds
                shape.path = path
                shape.strokeColor = color.cgColor
                shape.fillColor = annotation.type == .box ? color.withAlphaComponent(0.12).cgColor : nil
                let description: String
                switch annotation.type {
                case .box: description = String(localized: "AI highlighted area")
                case .arrow: description = String(localized: "AI coaching arrow")
                default: description = String(localized: "AI coaching drawing")
                }
                addSpokenMark(description, frame: path.boundingBoxOfPath.insetBy(dx: -4, dy: -4).intersection(bounds))
            }
        }
        for id in shapes.keys.filter({ !shapeIDs.contains($0) }) {
            shapes.removeValue(forKey: id)?.removeFromSuperlayer()
        }
        for id in labels.keys.filter({ !labelIDs.contains($0) }) {
            labels.removeValue(forKey: id)?.container.removeFromSuperview()
        }
        for label in labels.values { bringSubviewToFront(label.container) }
    }

    private func makeShape() -> CAShapeLayer {
        let shape = CAShapeLayer()
        shape.lineWidth = 2
        shape.lineCap = .round
        shape.lineJoin = .round
        layer.addSublayer(shape)
        return shape
    }

    private func makeLabel() -> (container: UIView, title: UILabel) {
        let container = UIView()
        container.isUserInteractionEnabled = false
        container.isAccessibilityElement = false
        container.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.9)
        container.layer.cornerRadius = 8
        container.layer.borderWidth = 1
        container.clipsToBounds = true
        let title = UILabel()
        title.numberOfLines = 0
        title.lineBreakMode = .byTruncatingTail
        title.textColor = .label
        title.adjustsFontForContentSizeCategory = true
        title.isAccessibilityElement = false
        title.isUserInteractionEnabled = false
        container.addSubview(title)
        addSubview(container)
        return (container, title)
    }

    private func addSpokenMark(_ text: String, frame: CGRect) {
        guard !frame.isEmpty, !frame.isNull else { return }
        let element = UIAccessibilityElement(accessibilityContainer: self)
        element.accessibilityLabel = text
        element.accessibilityTraits = .staticText
        element.accessibilityFrameInContainerSpace = frame
        spokenMarks.append(element)
    }

    private static func color(_ color: Models.Annotation.Color?) -> UIColor {
        switch color {
        case .blue: .systemBlue
        case .green: .systemGreen
        case .pink: .systemPink
        case .yellow, nil: .systemYellow
        }
    }

    private func withoutAnimations(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation(changes)
        CATransaction.commit()
    }

    enum Geometry {
        static func valid(_ bounds: CGRect) -> Bool {
            bounds.origin.x.isFinite && bounds.origin.y.isFinite && bounds.width.isFinite && bounds.height.isFinite
                && bounds.width > 0 && bounds.height > 0 && !bounds.isNull && !bounds.isInfinite
        }

        static func point(_ point: HonbakoPageCoachingModels.Point, in bounds: CGRect) -> CGPoint? {
            guard valid(bounds), HonbakoPageCoachingPolicy.valid(point) else { return nil }
            return CGPoint(x: bounds.minX + CGFloat(point.x) * bounds.width,
                           y: bounds.minY + CGFloat(point.y) * bounds.height)
        }

        static func rect(_ rect: HonbakoPageCoachingModels.Rect, in bounds: CGRect) -> CGRect? {
            guard valid(bounds), HonbakoPageCoachingPolicy.valid(rect) else { return nil }
            return CGRect(x: bounds.minX + CGFloat(rect.x) * bounds.width,
                          y: bounds.minY + CGFloat(rect.y) * bounds.height,
                          width: CGFloat(rect.width) * bounds.width,
                          height: CGFloat(rect.height) * bounds.height)
        }

        /// Insets can turn a tiny but valid normalized callout into CGRect.null
        /// (infinite origin). Never hand that frame to UIKit or Core Animation.
        static func labelContentFrame(in bounds: CGRect) -> CGRect? {
            guard valid(bounds), bounds.width > 12, bounds.height > 8 else { return nil }
            let frame = bounds.insetBy(dx: 6, dy: 4)
            return valid(frame) ? frame : nil
        }

        static func path(for annotation: HonbakoPageCoachingModels.Annotation, in bounds: CGRect) -> CGPath? {
            guard valid(bounds), HonbakoPageCoachingPolicy.valid(annotation) else { return nil }
            switch annotation.type {
            case .box:
                guard let value = annotation.rect, let frame = rect(value, in: bounds) else { return nil }
                return UIBezierPath(roundedRect: frame, cornerRadius: 5).cgPath
            case .arrow:
                guard let from = annotation.from, let to = annotation.to,
                      let start = point(from, in: bounds), let end = point(to, in: bounds) else { return nil }
                let dx = end.x - start.x, dy = end.y - start.y
                let length = hypot(dx, dy)
                guard length > 0 else { return nil }
                let head = min(14, length * 0.3)
                let unit = CGPoint(x: dx / length, y: dy / length)
                let path = CGMutablePath()
                path.move(to: start)
                path.addLine(to: end)
                path.move(to: CGPoint(x: end.x - unit.x * head - unit.y * head * 0.5,
                                     y: end.y - unit.y * head + unit.x * head * 0.5))
                path.addLine(to: end)
                path.addLine(to: CGPoint(x: end.x - unit.x * head + unit.y * head * 0.5,
                                        y: end.y - unit.y * head - unit.x * head * 0.5))
                return path
            case .stroke:
                guard let points = annotation.points,
                      let first = points.first.flatMap({ point($0, in: bounds) }) else { return nil }
                let path = CGMutablePath()
                path.move(to: first)
                for value in points.dropFirst() {
                    guard let next = point(value, in: bounds) else { return nil }
                    path.addLine(to: next)
                }
                return path
            case .label: return nil
            }
        }
    }
}
#endif
