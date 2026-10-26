#if SUMI
import SceneKit
import UIKit

/// A finite, orthographic book pile. SceneKit's render loop and frame link
/// exist only while a gesture or a bounded physics settle is in progress.
final class SumiBookPileView: UIView, UIGestureRecognizerDelegate {
    var openBook: ((SumiBook, SumiBookTransitionSource?) -> Void)?
    private let sceneView = SCNView()
    private let scene = SCNScene()
    private let cameraNode = SCNNode()
    private let boundaryRoot = SCNNode()
    private var transitionProxy: SumiPileTransitionProxy?
    private var transitionRenderer: SCNRenderer?
    private var frozenTransitionPlacement: (bookID: String, placement: SumiBookPilePlacement)?
    private var exactTransitionPoseIDs: Set<String> = []
    private var booksByID: [String: SumiPileBookNode] = [:]
    private var bookOrder: [String] = []
    private var elementsByID: [String: SumiPileBookAccessibilityElement] = [:]
    private var placements: [String: SumiBookPilePlacement] = [:]
    private var table = SumiBookPileLayout(count: 0)
    private var displayLink: CADisplayLink?
    private var displayLinkTarget: SumiPileDisplayLinkTarget?
    private var desiredActive = false
    private var sceneSuspended = false
    private var applicationSuspended = false
    private var hasRenderedFrame = false
    private var renderGeneration = 0
    private let rendererObserver = SumiPileRendererObserver()
    private var active: Bool {
        desiredActive && !sceneSuspended && !applicationSuspended
            && window?.windowScene?.activationState == .foregroundActive
    }
    private var needsSettlement = false
    private var stableFrames = 0
    private var wakeTime = 0.0
    private var lastViewport = CGSize.zero
    private var zoom = 1.0
    private var cameraCenter = CGPoint.zero
    private var initialZoom = 1.0
    private var initialCameraCenter = CGPoint.zero
    private var draggedBook: SumiPileBookNode?
    private var dragOffset = SCNVector3Zero
    private var cameraGestureCount = 0
    private static let placementKey = "Sumi.libraryPile.placements.v1"

    private lazy var bookPan = UIPanGestureRecognizer(target: self, action: #selector(dragBook(_:)))
    private lazy var canvasPan = UIPanGestureRecognizer(target: self, action: #selector(panCanvas(_:)))
    private lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(zoomCanvas(_:)))

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "Sumi.Library.Tabletop"
        accessibilityValue = "Books settled"
        accessibilityHint = "Drag a book to move it. Pinch to zoom or use two fingers to move the table."
        clipsToBounds = true
        if let data = UserDefaults.standard.data(forKey: Self.placementKey),
           let saved = try? JSONDecoder().decode([String: SumiBookPilePlacement].self, from: data) {
            placements = saved
        }
        configureScene()
        configureGestures()
        for name in [UIScene.didActivateNotification, UIScene.willDeactivateNotification,
                     UIScene.didEnterBackgroundNotification, UIApplication.didBecomeActiveNotification,
                     UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(sceneActivityChanged(_:)), name: name, object: nil)
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SumiBookPileView, _) in
            view.updatePaperColor()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func layoutSubviews() {
        super.layoutSubviews()
        sceneView.frame = bounds
        guard bounds.width > 1, bounds.height > 1 else { return }
        if lastViewport != bounds.size {
            lastViewport = bounds.size
            updateCamera()
        }
        updateBookFrames()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reconcileActivity()
    }

    func setActive(_ isActive: Bool) {
        desiredActive = isActive
        reconcileActivity()
    }

    private func reconcileActivity() {
        if !active { stopAndSave() }
        else if needsSettlement { wakeSimulation() }
        else { requestStaticFrame() }
        writePreviewDiagnostics()
    }

    @objc private func sceneActivityChanged(_ notification: Notification) {
        if let notifiedScene = notification.object as? UIScene, notifiedScene !== window?.windowScene { return }
        switch notification.name {
        case UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification: sceneSuspended = true
        case UIScene.didActivateNotification: sceneSuspended = false
        case UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification: applicationSuspended = true
        case UIApplication.didBecomeActiveNotification: applicationSuspended = false
        default: break
        }
        reconcileActivity()
    }

    func rendererDidRenderFrame(generation: Int) {
        guard generation == renderGeneration else { return }
        hasRenderedFrame = true
        booksByID.values.forEach { $0.hasRenderedPresentation = true }
        updateBookFrames()
        if active && needsSettlement && displayLink == nil { wakeSimulation() }
        writePreviewDiagnostics()
    }

    func setBooks(_ books: [SumiBook]) {
        let newIDs = books.map { $0.presentation.id }
        let structuralChange = newIDs != bookOrder
        let validIDs = Set(newIDs)
        for id in bookOrder where !validIDs.contains(id) {
            booksByID[id]?.cancelCoverLoad()
            booksByID[id]?.removeFromParentNode()
            booksByID.removeValue(forKey: id)
            elementsByID.removeValue(forKey: id)
            exactTransitionPoseIDs.remove(id)
        }
        if structuralChange {
            stopAndSave()
            let newTable = SumiBookPileLayout(count: books.count)
            let boundsChanged = newTable.width != table.width || newTable.height != table.height
            table = newTable
            rebuildBoundaries()
            for node in booksByID.values where boundsChanged {
                let bounded = table.bounded(.init(x: Double(node.position.x), y: Double(node.position.y),
                                                   z: Double(node.position.z), angle: Double(node.eulerAngles.z)))
                node.position = SCNVector3(Float(bounded.x), Float(bounded.y), Float(bounded.z))
                node.eulerAngles.z = Float(bounded.angle)
                node.physicsBody?.resetTransform()
                exactTransitionPoseIDs.remove(node.bookID)
                if let proxy = transitionProxy, proxy.bookID == node.bookID {
                    proxy.pose.simdTransform = node.simdWorldTransform
                    frozenTransitionPlacement = (node.bookID, bounded)
                    exactTransitionPoseIDs.insert(node.bookID)
                }
            }
        }
        var added = false
        for (index, book) in books.enumerated() {
            let id = book.presentation.id
            if let node = booksByID[id] {
                node.update(book: book)
            } else {
                let node = SumiPileBookNode(book: book)
                let placement = table.bounded(placements[id] ?? table.initialPlacement(id: id, index: index))
                node.position = SCNVector3(Float(placement.x), Float(placement.y), Float(placement.z))
                node.eulerAngles.z = Float(placement.angle)
                node.onTextureChanged = { [weak self] in self?.requestStaticFrame() }
                booksByID[id] = node
                scene.rootNode.addChildNode(node)
                elementsByID[id] = SumiPileBookAccessibilityElement(view: self, bookID: id)
                added = true
            }
            elementsByID[id]?.accessibilityLabel = [book.title, book.author, book.chapterLabel, book.pageLabel]
                .compactMap { $0 }.joined(separator: ", ")
        }
        bookOrder = newIDs
        if structuralChange {
            renderGeneration += 1
            hasRenderedFrame = false
            rendererObserver.requestFrame(generation: renderGeneration)
            updateCamera()
        }
        updateAccessibilityOrder()
        updateBookFrames()
        if added || structuralChange { needsSettlement = true; wakeSimulation() }
        else { requestStaticFrame() }
    }

    @discardableResult
    func openBook(withID id: String) -> Bool {
        guard let node = booksByID[id] else { return false }
        let source = transitionSource(for: id)
        openBook?(node.book, source)
        return true
    }

    /// A transparent rendering of this book alone, positioned at its actual
    /// frozen pose. Other books and the scene background never enter the proxy.
    @MainActor
    func transitionSource(for bookID: String) -> SumiBookTransitionSource? {
        if let transitionProxy, transitionProxy.bookID == bookID { return transitionProxy.source }
        transitionProxy?.source.finish()
        guard let node = booksByID[bookID], node.hasRenderedPresentation,
              window != nil, bounds.width > 1, bounds.height > 1 else { return nil }
        let pose = SCNNode()
        pose.simdTransform = displayLink != nil && !scene.isPaused
            ? node.presentation.simdWorldTransform : node.simdWorldTransform
        let captured = SumiBookPilePlacement(x: Double(pose.position.x), y: Double(pose.position.y),
                                             z: Double(pose.position.z), angle: Double(pose.eulerAngles.z))
        guard captured.x.isFinite, captured.y.isFinite, captured.z.isFinite, captured.angle.isFinite else { return nil }
        // Preserve this exact visible pose through every modal/background pause.
        // Conservative drag clearance must not shift the hidden source book.
        frozenTransitionPlacement = (bookID, captured)
        exactTransitionPoseIDs.insert(bookID)
        stopAndSave()
        let frame = projectedVolumeFrame(for: pose).insetBy(dx: -1, dy: -1)
        guard frame.width > 1, frame.height > 1,
              let image = isolatedBookImage(node: node, pose: pose, frame: frame) else {
            frozenTransitionPlacement = nil
            return nil
        }
        let proxy = UIImageView(image: image)
        proxy.frame = frame
        proxy.contentMode = .scaleToFill
        proxy.backgroundColor = .clear
        proxy.isOpaque = false
        proxy.isUserInteractionEnabled = false
        addSubview(proxy)
        node.isHidden = true
        let source = SumiBookTransitionSource(view: proxy) { [weak self, weak node, weak proxy] in
            node?.isHidden = false
            proxy?.removeFromSuperview()
            if self?.transitionProxy?.view === proxy {
                self?.transitionProxy = nil
                self?.frozenTransitionPlacement = nil
            }
            self?.requestStaticFrame()
        }
        transitionProxy = SumiPileTransitionProxy(bookID: bookID, pose: pose, view: proxy, source: source)
        requestStaticFrame()
        return source
    }

    private func isolatedBookImage(node: SumiPileBookNode, pose: SCNNode, frame: CGRect) -> UIImage? {
        let isolatedScene = SCNScene()
        isolatedScene.background.contents = UIColor.clear
        let book = SCNNode()
        book.simdTransform = pose.simdTransform
        for child in node.childNodes {
            let copy = child.clone()
            copy.physicsBody = nil
            book.addChildNode(copy)
        }
        isolatedScene.rootNode.addChildNode(book)
        let camera = cameraNode.clone()
        isolatedScene.rootNode.addChildNode(camera)
        for light in scene.rootNode.childNodes where light.light != nil {
            isolatedScene.rootNode.addChildNode(light.clone())
        }
        let renderer = transitionRenderer ?? SCNRenderer(device: sceneView.device, options: nil)
        transitionRenderer = renderer
        renderer.scene = isolatedScene
        renderer.pointOfView = camera
        defer {
            renderer.pointOfView = nil
            renderer.scene = nil
        }
        renderer.autoenablesDefaultLighting = false
        // Render the selected geometry at display resolution. Transparent
        // padding preserves its source rectangle at a viewport edge.
        let scale = min(3, max(1, traitCollection.displayScale))
        let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let snapshot = renderer.snapshot(atTime: sceneView.sceneTime, with: pixelSize, antialiasingMode: .multisampling4X)
        let imageRect = CGRect(x: frame.minX * scale, y: frame.minY * scale,
                               width: frame.width * scale, height: frame.height * scale).integral
        guard let cgImage = snapshot.cgImage else { return nil }
        // A transparent padded crop preserves the exact source frame even at
        // a viewport edge; the enclosing pile clips only the part not visible.
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let cropped = UIGraphicsImageRenderer(size: frame.size, format: format).image { _ in
            UIImage(cgImage: cgImage, scale: scale, orientation: .up)
                .draw(at: CGPoint(x: -imageRect.minX / scale, y: -imageRect.minY / scale))
        }
        return cropped
    }

    func stopAndSave() {
        let wasSimulating = displayLink != nil
        let heldBook = draggedBook
        displayLink?.invalidate()
        displayLink = nil
        displayLinkTarget = nil
        draggedBook?.physicsBody?.type = .dynamic
        draggedBook = nil
        cameraGestureCount = 0
        // Copy simulated presentation transforms before pausing. Saving model
        // positions would otherwise restore the books to their spawn positions.
        var saved: [String: SumiBookPilePlacement] = [:]
        for (id, node) in booksByID {
            let usePresentation = wasSimulating && node.hasRenderedPresentation && node !== heldBook
            let position = usePresentation ? node.presentation.position : node.position
            let angle = usePresentation ? node.presentation.eulerAngles.z : node.eulerAngles.z
            let measured = SumiBookPilePlacement(x: Double(position.x), y: Double(position.y),
                                                 z: Double(position.z), angle: Double(angle))
            let finite = measured.x.isFinite && measured.y.isFinite && measured.z.isFinite && measured.angle.isFinite
            let placement: SumiBookPilePlacement
            if let frozenTransitionPlacement, frozenTransitionPlacement.bookID == id {
                placement = frozenTransitionPlacement.placement
            } else if exactTransitionPoseIDs.contains(id), finite {
                // A returned book remains at its real physics pose. A later
                // drag or world resize explicitly reconciles its clearance.
                placement = measured
            } else {
                placement = table.bounded(measured)
            }
            node.position = SCNVector3(Float(placement.x), Float(placement.y), Float(placement.z))
            node.eulerAngles = SCNVector3(0, 0, Float(placement.angle))
            node.physicsBody?.clearAllForces()
            node.physicsBody?.velocity = SCNVector3Zero
            node.physicsBody?.angularVelocity = SCNVector4(0, 0, 1, 0)
            node.physicsBody?.resetTransform()
            saved[id] = placement
        }
        scene.isPaused = true
        sceneView.isPlaying = false
        sceneView.rendersContinuously = false
        accessibilityValue = "Books settled"
        if !saved.isEmpty {
            placements.merge(saved, uniquingKeysWith: { _, new in new })
            if let data = try? JSONEncoder().encode(placements) {
                UserDefaults.standard.set(data, forKey: Self.placementKey)
            }
        }
        updateBookFrames()
        requestStaticFrame()
        writePreviewDiagnostics()
    }

    func simulationTick(_ link: CADisplayLink) {
        guard active, window != nil else { stopAndSave(); return }
        updateBookFrames()
        guard draggedBook == nil, cameraGestureCount == 0 else { return }
        let now = CACurrentMediaTime()
        guard hasRenderedFrame else {
            // Never mistake an unrendered scene's zero velocities for rest.
            // Stop a failed renderer without erasing its pending settlement.
            if now - wakeTime > 8 { stopAndSave() }
            return
        }
        let quiet = booksByID.values.allSatisfy { node in
            guard let body = node.physicsBody else { return true }
            let velocity = body.velocity
            return body.isResting || (abs(velocity.x) + abs(velocity.y) + abs(velocity.z) < 0.025
                                      && abs(body.angularVelocity.w) < 0.025)
        }
        stableFrames = quiet && now - wakeTime > 0.65 ? stableFrames + 1 : 0
        if stableFrames >= 24 || now - wakeTime >= 8 {
            needsSettlement = false
            stopAndSave()
        }
    }

    func tearDown() {
        stopAndSave()
        booksByID.values.forEach { $0.cancelCoverLoad(); $0.onTextureChanged = nil }
        sceneView.delegate = nil
        rendererObserver.view = nil
        transitionProxy?.source.finish()
        transitionRenderer?.scene = nil
        transitionRenderer = nil
    }

    private func configureScene() {
        sceneView.scene = scene
        rendererObserver.view = self
        sceneView.delegate = rendererObserver
        sceneView.backgroundColor = .systemBackground
        sceneView.isOpaque = true
        sceneView.antialiasingMode = .multisampling4X
        sceneView.preferredFramesPerSecond = 120
        sceneView.rendersContinuously = false
        sceneView.isPlaying = false
        sceneView.accessibilityIdentifier = "Sumi.Library.Scene"
        sceneView.isAccessibilityElement = false
        addSubview(sceneView)
        scene.isPaused = true
        scene.physicsWorld.gravity = SCNVector3(0, 0, -9.8)
        scene.physicsWorld.timeStep = 1.0 / 120
        scene.rootNode.addChildNode(boundaryRoot)

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.zNear = 0.01
        camera.zFar = 100
        camera.wantsHDR = false
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 400
        ambient.color = UIColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
        let light = SCNLight()
        light.type = .directional
        light.intensity = 650
        light.castsShadow = true
        light.shadowMode = .deferred
        light.shadowColor = UIColor.black.withAlphaComponent(0.22)
        light.shadowRadius = 4
        light.shadowMapSize = CGSize(width: 1024, height: 1024)
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.eulerAngles = SCNVector3(-0.4, -0.45, -0.2)
        scene.rootNode.addChildNode(lightNode)
        updatePaperColor()
    }

    private func configureGestures() {
        bookPan.maximumNumberOfTouches = 1
        bookPan.delegate = self
        sceneView.addGestureRecognizer(bookPan)
        canvasPan.minimumNumberOfTouches = 2
        canvasPan.maximumNumberOfTouches = 2
        canvasPan.delegate = self
        sceneView.addGestureRecognizer(canvasPan)
        pinch.delegate = self
        sceneView.addGestureRecognizer(pinch)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapBook(_:)))
        tap.require(toFail: bookPan)
        sceneView.addGestureRecognizer(tap)
    }

    private func rebuildBoundaries() {
        boundaryRoot.childNodes.forEach { $0.removeFromParentNode() }
        let floorNode = SCNNode()
        floorNode.position.z = -0.085
        // The invisible collision floor and walls retain finite world bounds.
        let floorHull = SCNBox(width: table.width + 2, height: table.height + 2, length: 0.15, chamferRadius: 0)
        floorNode.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(geometry: floorHull, options: nil))
        floorNode.physicsBody?.friction = 0.72
        floorNode.physicsBody?.categoryBitMask = 1
        floorNode.physicsBody?.collisionBitMask = 2
        boundaryRoot.addChildNode(floorNode)
        for (x, y, width, height) in [
            (-table.width / 2 - 0.15, 0.0, 0.3, table.height + 1),
            (table.width / 2 + 0.15, 0.0, 0.3, table.height + 1),
            (0.0, -table.height / 2 - 0.15, table.width + 1, 0.3),
            (0.0, table.height / 2 + 0.15, table.width + 1, 0.3)
        ] {
            let wall = SCNNode(geometry: SCNBox(width: width, height: height, length: 10, chamferRadius: 0))
            wall.position = SCNVector3(Float(x), Float(y), 4.9)
            wall.opacity = 0
            wall.physicsBody = .static()
            wall.physicsBody?.categoryBitMask = 1
            wall.physicsBody?.collisionBitMask = 2
            boundaryRoot.addChildNode(wall)
        }
    }

    private func updatePaperColor() {
        backgroundColor = .systemBackground
        sceneView.backgroundColor = .systemBackground
        scene.background.contents = UIColor.systemBackground.resolvedColor(with: traitCollection)
        requestStaticFrame()
    }

    private func wakeSimulation() {
        guard active, window != nil else { requestStaticFrame(); return }
        stableFrames = 0
        wakeTime = CACurrentMediaTime()
        scene.isPaused = false
        sceneView.isPlaying = true
        sceneView.rendersContinuously = true
        accessibilityValue = "Moving books"
        if displayLink == nil {
            let target = SumiPileDisplayLinkTarget(view: self)
            let link = CADisplayLink(target: target, selector: #selector(SumiPileDisplayLinkTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
            displayLinkTarget = target
            displayLink = link
            link.add(to: .main, forMode: .common)
        }
    }

    private func requestStaticFrame() { sceneView.setNeedsDisplay() }

    private func updateCamera() {
        guard bounds.width > 1, bounds.height > 1, let camera = cameraNode.camera else { return }
        let aspect = min(8, max(0.15, Double(bounds.width / bounds.height)))
        let tiltCosine = 25.0 / hypot(25.0, 3.6)
        zoom = min(maximumZoom, max(1, zoom.isFinite ? zoom : 1))
        // Orthographic scale is a vertical half-extent in camera coordinates.
        // Account for the fixed tabletop tilt analytically. Querying unproject
        // here is unsafe before SceneKit has rendered its first camera matrix.
        let halfHeight = max((table.height + 0.7) * tiltCosine,
                             (table.width + 0.7) / aspect) / (2 * zoom)
        camera.orthographicScale = min(1_000, max(0.6, halfHeight))
        let visibleHalfWidth = camera.orthographicScale * aspect
        let visibleHalfTableHeight = camera.orthographicScale / tiltCosine
        let xLimit = CGFloat(max(0, table.width / 2 + 0.4 - visibleHalfWidth))
        let yLimit = CGFloat(max(0, table.height / 2 + 0.4 - visibleHalfTableHeight))
        cameraCenter.x = min(xLimit, max(-xLimit, cameraCenter.x.isFinite ? cameraCenter.x : 0))
        cameraCenter.y = min(yLimit, max(-yLimit, cameraCenter.y.isFinite ? cameraCenter.y : 0))
        positionCamera()
        updateBookFrames()
        requestStaticFrame()
        writePreviewDiagnostics()
    }

    private func writePreviewDiagnostics() {
        #if DEBUG
        // This flag is the root's generated, in-memory fixture harness. Never
        // export a real library's identities, coordinates or reading state.
        guard ProcessInfo.processInfo.arguments.contains("--sumi-library-check"),
              let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let projectedBooks: [[String: Any]] = bookOrder.compactMap { id in
            guard let node = booksByID[id] else { return nil }
            let frame = projectedFrame(for: node)
            let position = node.hasRenderedPresentation ? node.presentation.position : node.position
            return ["id": id, "frame": [frame.minX, frame.minY, frame.width, frame.height],
                    "position": [position.x, position.y, position.z]]
        }
        let payload: [String: Any] = [
            "bounds": [bounds.width, bounds.height], "cameraScale": cameraNode.camera?.orthographicScale ?? 0,
            "cameraCenter": [cameraCenter.x, cameraCenter.y], "zoom": zoom,
            "simulationRunning": displayLink != nil, "books": projectedBooks,
            "desiredActive": desiredActive, "effectiveActive": active,
            "windowSceneState": window?.windowScene?.activationState.rawValue ?? -999,
            "rendererReady": hasRenderedFrame, "scenePaused": scene.isPaused,
            "rendererPlaying": sceneView.isPlaying,
            "sceneViewBounds": [sceneView.bounds.width, sceneView.bounds.height]
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: cache.appendingPathComponent("SumiLibraryPreviewDiagnostics.json"), options: .atomic)
        #endif
    }

    private func positionCamera() {
        let center = SCNVector3(Float(cameraCenter.x), Float(cameraCenter.y), 0)
        cameraNode.position = SCNVector3(center.x, center.y - 3.6, 25)
        cameraNode.look(at: center, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    }

    private func worldPoint(_ point: CGPoint, z: Float = 0) -> SCNVector3 {
        guard bounds.height > 1, let camera = cameraNode.camera else { return SCNVector3Zero }
        let halfHeight = max(0.6, camera.orthographicScale)
        let worldPerPoint = 2 * halfHeight / Double(bounds.height)
        let cosine = 25.0 / hypot(25.0, 3.6)
        let sine = 3.6 / hypot(25.0, 3.6)
        let x = Double(cameraCenter.x) + Double(point.x - bounds.midX) * worldPerPoint
        let y = Double(cameraCenter.y) + (Double(bounds.midY - point.y) * worldPerPoint - Double(z) * sine) / cosine
        return SCNVector3(Float(x), Float(y), z)
    }

    private func projectWorldPoint(_ point: SCNVector3) -> CGPoint {
        guard bounds.height > 1, let camera = cameraNode.camera else { return .zero }
        let pointsPerWorld = Double(bounds.height) / (2 * max(0.6, camera.orthographicScale))
        let cosine = 25.0 / hypot(25.0, 3.6)
        let sine = 3.6 / hypot(25.0, 3.6)
        let x = Double(bounds.midX) + (Double(point.x) - Double(cameraCenter.x)) * pointsPerWorld
        let y = Double(bounds.midY) - ((Double(point.y) - Double(cameraCenter.y)) * cosine + Double(point.z) * sine) * pointsPerWorld
        return CGPoint(x: x, y: y)
    }

    private func projectedFrame(for node: SumiPileBookNode) -> CGRect {
        let halfWidth = Float(SumiBookPileLayout.bookWidth / 2)
        let halfHeight = Float(SumiBookPileLayout.bookHeight / 2)
        let corners = [SCNVector3(-halfWidth, -halfHeight, 0.1), SCNVector3(halfWidth, -halfHeight, 0.1),
                       SCNVector3(-halfWidth, halfHeight, 0.1), SCNVector3(halfWidth, halfHeight, 0.1)]
            .map { point in
                let usePresentation = displayLink != nil && !scene.isPaused && node.hasRenderedPresentation
                let world = usePresentation
                    ? node.presentation.convertPosition(point, to: nil) : node.convertPosition(point, to: nil)
                return projectWorldPoint(world)
            }
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
              minX.isFinite, maxX.isFinite, minY.isFinite, maxY.isFinite else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func updateBookFrames() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        for id in bookOrder {
            guard let node = booksByID[id] else { continue }
            elementsByID[id]?.accessibilityFrameInContainerSpace = projectedFrame(for: node)
        }
        if let transitionProxy {
            transitionProxy.view.frame = projectedVolumeFrame(for: transitionProxy.pose).insetBy(dx: -1, dy: -1)
            bringSubviewToFront(transitionProxy.view)
        }
    }

    private func projectedVolumeFrame(for pose: SCNNode) -> CGRect {
        let halfWidth = Float(SumiBookPileLayout.bookWidth / 2)
        let halfHeight = Float(SumiBookPileLayout.bookHeight / 2)
        let halfDepth = Float(SumiBookPileLayout.bookDepth / 2)
        var points: [CGPoint] = []
        for x in [-halfWidth, halfWidth] {
            for y in [-halfHeight, halfHeight] {
                for z in [-halfDepth, halfDepth] {
                    points.append(projectWorldPoint(pose.convertPosition(SCNVector3(x, y, z), to: nil)))
                }
            }
        }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
              minX.isFinite, maxX.isFinite, minY.isFinite, maxY.isFinite else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func updateAccessibilityOrder() {
        accessibilityElements = bookOrder.compactMap { elementsByID[$0] }
    }

    private func book(at point: CGPoint) -> SumiPileBookNode? {
        for hit in sceneView.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue]) {
            var node: SCNNode? = hit.node
            while let candidate = node {
                if let book = candidate as? SumiPileBookNode { return book }
                node = candidate.parent
            }
        }
        return nil
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard active else { return false }
        if gestureRecognizer === bookPan {
            return hasRenderedFrame && book(at: gestureRecognizer.location(in: sceneView)) != nil
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        (gestureRecognizer === canvasPan && otherGestureRecognizer === pinch)
            || (gestureRecognizer === pinch && otherGestureRecognizer === canvasPan)
    }

    @objc private func tapBook(_ gesture: UITapGestureRecognizer) {
        guard active, hasRenderedFrame, gesture.state == .ended, let node = book(at: gesture.location(in: sceneView)) else { return }
        openBook(withID: node.bookID)
    }

    @objc private func dragBook(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: sceneView)
        switch gesture.state {
        case .began:
            guard let node = book(at: point) else { return }
            exactTransitionPoseIDs.remove(node.bookID)
            let current = node.presentation.position
            node.position = current
            node.eulerAngles = node.presentation.eulerAngles
            node.physicsBody?.clearAllForces()
            node.physicsBody?.type = .kinematic
            node.physicsBody?.resetTransform()
            draggedBook = node
            needsSettlement = true
            let highest = booksByID.values.map { $0.presentation.position.z }.max() ?? current.z
            node.position.z = min(3.5, max(current.z + 0.16, highest + 0.23))
            let world = worldPoint(point, z: node.position.z)
            dragOffset = SCNVector3(current.x - world.x, current.y - world.y, 0)
            wakeSimulation()
        case .changed:
            guard let node = draggedBook else { return }
            let world = worldPoint(point, z: node.position.z)
            let placement = table.bounded(.init(x: Double(world.x + dragOffset.x), y: Double(world.y + dragOffset.y),
                                                z: Double(node.position.z), angle: Double(node.eulerAngles.z)))
            node.position.x = Float(placement.x)
            node.position.y = Float(placement.y)
            node.physicsBody?.resetTransform()
            wakeSimulation()
            updateBookFrames()
        case .ended, .cancelled, .failed:
            guard let node = draggedBook else { return }
            node.physicsBody?.type = .dynamic
            node.physicsBody?.resetTransform()
            let velocity = gesture.state == .ended ? gesture.velocity(in: sceneView) : .zero
            let from = worldPoint(point, z: node.position.z)
            let to = worldPoint(CGPoint(x: point.x + velocity.x / 10, y: point.y + velocity.y / 10), z: node.position.z)
            let impulse = SumiBookPileLayout.throwVelocity(x: Double(to.x - from.x) * 10, y: Double(to.y - from.y) * 10)
            node.physicsBody?.velocity = SCNVector3(Float(impulse.dx), Float(impulse.dy), 0)
            node.physicsBody?.angularVelocity = SCNVector4(0, 0, 1, Float(max(-1.2, min(1.2, velocity.x / 1700))))
            saveCurrentPlacements(overriding: node)
            draggedBook = nil
            wakeSimulation()
        default: break
        }
    }

    /// Persist the release and final pose once each. Backgrounding captures
    /// the current pose once; simulation frames never write preferences.
    private func saveCurrentPlacements(overriding releasedBook: SumiPileBookNode? = nil) {
        for (id, node) in booksByID {
            let useModel = !node.hasRenderedPresentation || node === draggedBook || node === releasedBook
            let position = useModel ? node.position : node.presentation.position
            placements[id] = table.bounded(.init(x: Double(position.x), y: Double(position.y), z: Double(position.z),
                                                  angle: Double(useModel ? node.eulerAngles.z : node.presentation.eulerAngles.z)))
        }
        if let data = try? JSONEncoder().encode(placements) { UserDefaults.standard.set(data, forKey: Self.placementKey) }
    }

    @objc private func panCanvas(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began: initialCameraCenter = cameraCenter; cameraGestureCount += 1; wakeSimulation()
        case .changed:
            let translation = gesture.translation(in: sceneView)
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let from = worldPoint(center)
            let to = worldPoint(CGPoint(x: center.x + translation.x, y: center.y + translation.y))
            cameraCenter = CGPoint(x: initialCameraCenter.x - CGFloat(to.x - from.x),
                                   y: initialCameraCenter.y - CGFloat(to.y - from.y))
            updateCamera()
        case .ended, .cancelled, .failed: cameraGestureCount = max(0, cameraGestureCount - 1); wakeSimulation()
        default: break
        }
    }

    @objc private func zoomCanvas(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began: initialZoom = zoom; cameraGestureCount += 1; wakeSimulation()
        case .changed: zoom = min(maximumZoom, max(1, initialZoom * Double(gesture.scale))); updateCamera()
        case .ended, .cancelled, .failed: cameraGestureCount = max(0, cameraGestureCount - 1); wakeSimulation()
        default: break
        }
    }

    private var maximumZoom: Double { max(5, table.height / 5.8) }

}
#endif
