import UIKit

/// A spread owns two independent leaves. Binding lighting stays on each leaf,
/// while the unlit centre sits underneath the paper and its moving curl.
final class ReaderBookSpreadViewController: BaseViewController {
    let leaves: [UIViewController]
    #if SUMI
    private let spine = ReaderBookSpineView()
    private var bindingLighting: [ObjectIdentifier: CALayer] = [:]
    #endif

    init(leaves: [UIViewController]) {
        self.leaves = leaves
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func configure() { attachLeaves() }

    func attachLeaves() {
        loadViewIfNeeded()
        #if SUMI
        view.backgroundColor = SumiPaperSurface.backgroundColor
        if spine.superview !== view { view.insertSubview(spine, at: 0) }
        #endif
        for leaf in leaves where leaf.parent !== self {
            leaf.remove()
            addChild(leaf)
            leaf.view.translatesAutoresizingMaskIntoConstraints = true
            leaf.view.autoresizingMask = []
            view.addSubview(leaf.view)
            leaf.didMove(toParent: self)
        }
        #if SUMI
        // A canonical page can have been hidden as a portrait curl surface.
        // Its new spread is the visible owner now, so restore both leaves.
        for leaf in leaves { leaf.view.isHidden = false }
        updateAccessibilityLeaves()
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard leaves.count == 2 else { return }
        // UIStackView rounds half-point edges differently at 3x. Native center
        // curl uses exact halves; matching them keeps each Fill Width baseline
        // and rendered image scale identical when Reduce Motion changes live.
        let half = view.bounds.width / 2
        for (index, leaf) in leaves.enumerated() where leaf.parent === self {
            let frame = CGRect(x: view.bounds.minX + CGFloat(index) * half, y: view.bounds.minY,
                               width: half, height: view.bounds.height)
            if leaf.view.frame != frame { leaf.view.frame = frame }
#if SUMI
            let edge: ReaderBookSpineView.BindingEdge = index == 0 ? .right : .left
            if let page = leaf as? ReaderPageViewController {
                page.bookBindingEdge = edge
                page.updatePaperShape()
            } else if let wide = leaf as? ReaderBookWideLeafViewController {
                wide.bookBindingEdge = edge
                wide.updatePaperShape()
            } else if let index = leaf as? SumiIndexLeafViewController {
                index.bookBindingEdge = edge
                index.updatePaperShape()
            } else if let blank = leaf as? ReaderBookBlankViewController {
                blank.bookBindingEdge = edge
                blank.view.setNeedsLayout()
            }
            updateBindingLighting(for: leaf, edge: edge)
#endif
            leaf.view.layoutIfNeeded()
        }
        #if SUMI
        spine.update(pageFrames: leaves.filter { $0.parent === self }.map { $0.view.frame }, enabled: true)
        #endif
    }

    func releaseLeaves() {
        #if SUMI
        bindingLighting.values.forEach { $0.removeFromSuperlayer() }
        bindingLighting.removeAll()
        #endif
        for leaf in leaves where leaf.parent === self {
            #if SUMI
            if let page = leaf as? ReaderPageViewController { page.bookBindingEdge = .none }
            if let wide = leaf as? ReaderBookWideLeafViewController { wide.bookBindingEdge = .none }
            #endif
            leaf.remove()
        }
        #if SUMI
        updateAccessibilityLeaves()
        #endif
    }

    #if SUMI
    private func updateBindingLighting(for leaf: UIViewController, edge: ReaderBookSpineView.BindingEdge) {
        let identity = ObjectIdentifier(leaf)
        let lighting: CALayer
        if let existing = bindingLighting[identity] { lighting = existing }
        else {
            // Keep this light on the physical leaf. Snapshotting the leaf also
            // captures its curved shoulder, which bends with the page mesh.
            lighting = CALayer()
            lighting.name = ReaderBookSpineView.bindingLightingName
            lighting.zPosition = 32
            bindingLighting[identity] = lighting
        }
        if lighting.superlayer !== leaf.view.layer { leaf.view.layer.addSublayer(lighting) }
        ReaderBookSpineView.updateBindingLighting(lighting, in: leaf.view.bounds, edge: edge)
    }

    private func updateAccessibilityLeaves() {
        // A plain UIKit chapter-index leaf and an AS image leaf share this
        // spread. Enumerate both containers, keeping native table rows intact.
        node.isAccessibilityElement = false
        node.accessibilityElements = leaves.filter { $0.parent === self && !$0.view.isHidden }.map { $0.view! }
    }
    #endif
}

final class ReaderBookBlankViewController: BaseViewController {
#if SUMI
    var bookBindingEdge: ReaderBookSpineView.BindingEdge = .none
    private let paperMask = CAShapeLayer()

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        paperMask.frame = view.bounds
        if bookBindingEdge == .none { ReaderBookSpineView.removeBindingLighting(from: view.layer) }
        paperMask.path = ReaderBookSpineView.pagePath(in: view.bounds, bindingEdge: bookBindingEdge)
        view.layer.mask = paperMask
        CATransaction.commit()
    }
#endif
    override func configure() {
        #if SUMI
        view.backgroundColor = SumiPaperSurface.backgroundColor
        #else
        view.backgroundColor = .systemBackground
        #endif
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
    }
}
