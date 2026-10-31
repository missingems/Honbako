import Foundation
import RealityKit
import simd

/// The iPhone Duo that Xcode 27.1's DeviceHub draws, folded the way DeviceHub folds it, with the
/// simulator's native framebuffers shown on the model's own screen meshes.
///
/// The model is DeviceKit's `V68.usdz`, which ships inside Xcode; the client's build copies it into
/// the app (`Client/Scripts/copy-device-models.sh`). RealityKit only, so the same code builds for
/// macOS, where the tests run, and visionOS.
///
/// ```swift
/// let duo = try await DuoModel.load(contentsOf: url)
/// content.add(duo.root)  // metres, life size
/// duo.setMaterial(VideoMaterial(videoRenderer: innerRenderer), for: .inner)  // native 2007×2853
/// duo.setMaterial(VideoMaterial(videoRenderer: coverRenderer), for: .cover)  // native 1398×2034
/// duo.setHinge(angleDegrees: 90)  // commanded angle: 0 closed, 180 flat
/// let hit = duo.hitTest(origin: origin, direction: direction)  // display and native pixel, or nil
/// ```
///
/// - The angle is the commanded one: CMAngle, what devicectl reports, the angle between the two
///   inner halves. Never feed it UIHinge readings, which differ between 0 and 180 on the vendor
///   path (5 + 170c/180, spec §4.3). Non-finite angles are ignored.
/// - The fold is the file's own `book_close` clip at the clip time DeviceHub uses for the angle,
///   written straight from the clip's sampled frames. Turning the two leaf joints alone would leave
///   the crease strip and the hinge plate flat, and they tear.
/// - Which part stays still is a choice (`FoldAnchor`). The default, `.cameraLeaf`, is spec §3.3's
///   layout: the camera leaf stays and the cover leaf turns about the hinge line, so a closed
///   device shows its cover to whoever faced the flat inner screen.
/// - The inner mesh's UVs are rewritten so a native framebuffer lands the right way up (the file's
///   expect the upright 2853×2007 image), and the cover camera trims move onto the cover's material,
///   as DeviceHub does, so they show the framebuffer's own camera disc.
/// - Each screen moves into a skinned entity of its own (`screenEntities`): a VideoMaterial on one
///   slot of the 33-material body hid the rest of the body in RealityRenderer.
/// - Closed (at most 0.5°, DeviceHub's epsilon) the inner screen shows black, as the real LCD-1
///   does, so a VideoMaterial holding the last open frame cannot show through the closed seam.
/// - Every part of the rebuilt meshes gets an index count padded with degenerate triangles, so
///   each part's index data starts 16-byte aligned: visionOS's render server crashes otherwise
///   (`paddingIndicesToAlignment(_:)`).
/// - The screens and the opaque body are skinned on the CPU for touches (`hitTest`, where the body
///   occludes as it does on the GPU, and `pixel(nearestTo:)`), posed bounds and colliders.
///
/// RealityKit's `visualBounds` and `generateCollisionShapes` see the bind (flat) pose only, so never
/// use them on this model: use `posedBounds()`, `leafTransform(_:)` and `screenCollisionShape(for:)`.
@MainActor
public final class DuoModel {
  // MARK: - Entities

  /// Add this to the scene. Metres, 1:1, in the model's axes: +Y is the inner screen's normal when
  /// flat, X runs across the fold (the cover leaf is at -X), and -Z is the top edge, with the
  /// cameras and volume buttons.
  public let root: Entity
  /// Carries the anchor transform: a rotation about the hinge line, or DeviceHub's recentring.
  public let foldFrame: Entity
  /// The loaded file's top entity, scaled 0.01 because the file is in centimetres.
  public let fileRoot: Entity
  /// The skinned entity holding the body's meshes and the 31-joint skeleton. With
  /// `.separateEntities` the screens move out of it into `screenEntities`.
  public let modelEntity: ModelEntity
  /// The entity whose AnimationLibraryComponent holds the file's named clips ("root").
  public let clipEntity: Entity

  // MARK: - State

  /// The commanded hinge angle in degrees: 0 closed, 180 flat.
  public private(set) var hingeAngleDegrees: Double = 180
  public var anchor: FoldAnchor {
    didSet { applyPose() }
  }
  public let driver: PoseDriver
  public let innerMapping: InnerMapping
  public let blankInnerWhenClosed: Bool
  /// True while the inner screen shows black because the hinge is closed.
  public private(set) var isInnerBlanked = false
  public private(set) var spring = HingeSpring()
  var hasInitializedHinge = false

  /// Material slot indices in the body, found by material name after loading.
  ///
  /// They are not stable across launches: RealityKit orders the 33 materials differently from one
  /// process to the next (the cover was slot 0, 1, 2, 12, 21, 22, 23, 26 and 28 in different
  /// launches). Never persist or hard-code them.
  public internal(set) var slots: [Display: [Int]] = [:]
  /// With `.separateEntities`, the skinned entity carrying each screen, as material slot 0. Put
  /// input and collision components on these, so the targeted entity names the display.
  public internal(set) var screenEntities: [Display: ModelEntity] = [:]
  public let screenHosting: ScreenHosting

  // MARK: - The fold clip

  /// Where `book_close` starts in the file's timeline, and how long it is, as RealityKit reports it.
  public let foldClipStart: TimeInterval
  public let foldClipDuration: TimeInterval
  public let foldClip: AnimationResource
  /// The file frames the sampled driver interpolates between: `book_close`'s own, 260...390 in
  /// V68.usdz.
  public let sampledFrameWindow: ClosedRange<Int>
  /// `book_close`'s sampled frames, with the file's joint order mapped to the model's.
  let frameInterval: Double
  let sampledStart: Double
  let frames: [[Transform]]
  let sampledToModelJoint: [Int]
  var controller: AnimationPlaybackController?

  /// The hinge line in foldFrame space (metres). `hingeLine` gives it in root space for the
  /// current anchor.
  public let hingePoint: SIMD3<Float>
  public let hingeAxis: SIMD3<Float>
  let centeringOffset: SIMD3<Float>

  /// Milliseconds spent in each loading step, for diagnostics.
  public private(set) var loadTimingsMS: [String: Double] = [:]

  // MARK: - CPU geometry

  var screenMeshes: [Display: ScreenMesh] = [:]
  var bodyParts: [BodyPart] = []
  var screenSlotSet = Set<Int>()
  var transparentSlotSet = Set<Int>()
  var poseCache: PoseCache?
  /// The body's mesh contents between the deferred init and `prepareScreensAsync`. Read once:
  /// each read of `MeshResource.contents` copies all 73 parts, about 25 ms.
  var pendingContents: MeshResource.Contents?

  /// The cover fit behind the camera fill: its worst residual over the cover's vertices, in native
  /// pixels, and where each camera trim's centre lands in the cover framebuffer.
  public internal(set) var coverFitResidualPx: Double = .nan
  public internal(set) var cameraTrimCentresPx: [String: SIMD2<Double>] = [:]
  let parentIndices: [Int?]
  let inverseBind: [simd_float4x4]
  /// Model space (cm) to root space (m) with foldFrame at identity: the flat, unanchored rest frame.
  let restModelToRoot: simd_float4x4
  let leafJointIndex: [Leaf: Int]
  var clientMaterials: [Display: any Material] = [:]
  var fileMaterials: [Display: any Material] = [:]
  let blackMaterial: UnlitMaterial

  // MARK: - Loading

  /// Loads the model and prepares its screens.
  ///
  /// After the file load, the main actor is held only for the rig and screen preparation (about
  /// 5 ms on a Mac). The meshes are built with RealityKit's async `MeshResource(from:)` while the
  /// body's CPU copy for hit testing is read off the main actor (see `loadTimingsMS`). Show a
  /// loading state until it returns.
  public static func load(contentsOf url: URL, options: Options = Options()) async throws -> DuoModel {
    let start = Date()
    let top: Entity
    if let variant = options.colorVariant {
      let catalog = try await Entity.ConfigurationCatalog(from: url)
      top = try await Entity(from: catalog, configurations: ["color": variant])
    } else {
      top = try await Entity(contentsOf: url)
    }
    let duo = try DuoModel(fileRoot: top, options: options, prepareScreensNow: false)
    duo.loadTimingsMS["fileLoad"] = Date().timeIntervalSince(start) * 1000 - (duo.loadTimingsMS["rig"] ?? 0)
    try await duo.prepareScreensAsync(coverCameraFill: options.coverCameraFill)
    return duo
  }

  /// Everything on the main actor, mesh building and the body's CPU copy included: about 55 ms on
  /// a Mac. Prefer `load`.
  public convenience init(fileRoot top: Entity, options: Options = Options()) throws {
    try self.init(fileRoot: top, options: options, prepareScreensNow: true)
  }

  private init(fileRoot top: Entity, options: Options, prepareScreensNow: Bool) throws {
    let start = Date()
    guard let model = Self.findModelEntity(in: top),
      let meshContents = model.model?.mesh.contents,
      meshContents.models.contains(where: { $0.parts.contains { $0.id == Display.inner.partID } })
    else {
      throw LoadError(description: "no skinned ModelEntity containing the inner screen part \(Display.inner.partID)")
    }
    guard let (clipOwner, clip) = Self.findClip(named: Rig.foldClipName, in: top) else {
      throw LoadError(description: "no \(Rig.foldClipName) clip in any AnimationLibraryComponent")
    }
    guard let view = clip.definition as? AnimationView, let sampled = Self.leafJointAnimation(in: clip.definition) else {
      throw LoadError(description: "\(Rig.foldClipName) is not an AnimationView over a SampledAnimation<JointTransforms>")
    }
    fileRoot = top
    modelEntity = model
    clipEntity = clipOwner
    foldClip = clip
    driver = options.driver
    innerMapping = options.innerMapping
    anchor = options.anchor
    screenHosting = options.screenHosting
    blankInnerWhenClosed = options.blankInnerWhenClosed
    blackMaterial = UnlitMaterial(color: .black, applyPostProcessToneMap: false)
    foldClipStart = view.trimStart ?? 0
    foldClipDuration = clip.definition.duration

    // Keep the frames book_close covers, remapped to the model's joint order. The frame interval
    // is a Float (1/24 = 0.0416666679), so the clip start lands at frame 259.99999: snap to the
    // nearest frame first, or the window starts a frame early.
    let interval = Double(sampled.frameInterval)
    frameInterval = interval
    func frameIndex(_ t: Double, _ rounding: FloatingPointRoundingRule) -> Int {
      let f = (t - sampled.start) / interval
      return Int(abs(f - f.rounded()) < 1e-3 ? f.rounded() : f.rounded(rounding))
    }
    let startFrame = frameIndex(foldClipStart, .down)
    let endFrame = frameIndex(foldClipStart + foldClipDuration, .up)
    // Read once: the property copies every frame on each access.
    let allFrames = sampled.frames
    let lo = min(max(0, startFrame), allFrames.count - 1)
    let hi = max(lo, min(allFrames.count - 1, endFrame))
    sampledFrameWindow = lo...hi
    sampledStart = sampled.start + Double(lo) * interval
    frames = (lo...hi).map { Array(allFrames[$0]) }
    let names = model.jointNames
    var map: [Int] = []
    for name in sampled.jointNames {
      guard let i = names.firstIndex(of: name) else {
        throw LoadError(description: "clip joint \(name) not in the model")
      }
      map.append(i)
    }
    sampledToModelJoint = map
    var leaves: [Leaf: Int] = [:]
    for leaf in Leaf.allCases {
      guard let i = names.firstIndex(where: { $0 == leaf.jointName || $0.hasSuffix("/" + leaf.jointName) }) else {
        throw LoadError(description: "no \(leaf) leaf joint \(leaf.jointName)")
      }
      leaves[leaf] = i
    }
    leafJointIndex = leaves

    guard let skeleton = meshContents.skeletons.first, skeleton.joints.count == names.count else {
      throw LoadError(description: "no skeleton with \(names.count) joints")
    }
    parentIndices = skeleton.joints.map(\.parentIndex)
    inverseBind = skeleton.joints.map(\.inverseBindPoseMatrix)

    // root -> foldFrame -> the file's top entity (scale 0.01) -> ... -> modelEntity.
    let rootEntity = Entity()
    rootEntity.name = "DuoModel"
    let frameEntity = Entity()
    frameEntity.name = "DuoFoldFrame"
    rootEntity.addChild(frameEntity)
    frameEntity.addChild(top)
    root = rootEntity
    foldFrame = frameEntity
    let toFrame = model.transformMatrix(relativeTo: frameEntity)
    restModelToRoot = toFrame
    let point = toFrame * SIMD4<Float>(Rig.hingePointCM, 1)
    hingePoint = SIMD3(point.x, point.y, point.z)
    let axis = toFrame * SIMD4<Float>(Rig.hingeAxis, 0)
    hingeAxis = normalize(SIMD3(axis.x, axis.y, axis.z))
    let offset = toFrame * SIMD4<Float>(Rig.foldCenteringOffsetCM, 0)
    centeringOffset = SIMD3(offset.x, offset.y, offset.z)
    loadTimingsMS["rig"] = Date().timeIntervalSince(start) * 1000

    if prepareScreensNow {
      let t1 = Date()
      nonisolated(unsafe) let built = try buildScreenContents(from: meshContents, coverCameraFill: options.coverCameraFill)
      let t2 = Date()
      bodyParts = Self.extractBodyParts(from: built.host, screenSlots: screenSlotSet, transparentSlots: transparentSlotSet)
      let t3 = Date()
      let bodyMesh = try MeshResource.generate(from: Self.paddingIndicesToAlignment(built.host))
      var screenMeshesGPU: [Display: MeshResource] = [:]
      for (display, contents) in built.screens {
        screenMeshesGPU[display] = try MeshResource.generate(from: Self.paddingIndicesToAlignment(contents))
      }
      loadTimingsMS["prepare"] = t2.timeIntervalSince(t1) * 1000
      loadTimingsMS["cpuBody"] = t3.timeIntervalSince(t2) * 1000
      loadTimingsMS["meshes"] = Date().timeIntervalSince(t3) * 1000
      install(body: bodyMesh, screens: screenMeshesGPU)
    } else {
      pendingContents = meshContents
    }
    applyPose()
  }

  private func prepareScreensAsync(coverCameraFill: Bool) async throws {
    let t1 = Date()
    guard let contents = pendingContents else {
      throw LoadError(description: "screens already prepared")
    }
    pendingContents = nil
    nonisolated(unsafe) let built = try buildScreenContents(from: contents, coverCameraFill: coverCameraFill)
    loadTimingsMS["prepare"] = Date().timeIntervalSince(t1) * 1000
    let t2 = Date()
    let screenSlots = screenSlotSet
    let transparentSlots = transparentSlotSet
    // The contents are only read from here on, by the extraction, the padding and
    // MeshResource(from:).
    let box = UncheckedBox(value: built)
    let extraction = Task.detached(priority: .userInitiated) { () -> ([BodyPart], Double) in
      let t = Date()
      let parts = Self.extractBodyParts(from: box.value.host, screenSlots: screenSlots, transparentSlots: transparentSlots)
      return (parts, Date().timeIntervalSince(t) * 1000)
    }
    // Only the GPU meshes get padded index data (`paddingIndicesToAlignment`); it reads every
    // part's indices, so it runs off the main actor too.
    let padding = Task.detached(priority: .userInitiated) { () -> UncheckedBox<BuiltContents> in
      UncheckedBox(value: BuiltContents(
        host: Self.paddingIndicesToAlignment(box.value.host),
        screens: box.value.screens.map { ($0.0, Self.paddingIndicesToAlignment($0.1)) }
      ))
    }
    let padded = await padding.value.value
    nonisolated(unsafe) let host = padded.host
    let bodyMesh = try await MeshResource(from: host)
    var screenMeshesGPU: [Display: MeshResource] = [:]
    for (display, contents) in padded.screens {
      nonisolated(unsafe) let screenContents = contents
      screenMeshesGPU[display] = try await MeshResource(from: screenContents)
    }
    loadTimingsMS["meshes"] = Date().timeIntervalSince(t2) * 1000
    let (parts, extractionMS) = await extraction.value
    bodyParts = parts
    loadTimingsMS["cpuBody"] = extractionMS
    install(body: bodyMesh, screens: screenMeshesGPU)
    applyPose()
  }

  /// The skinned body: the entity the file names DgmOwZEmClRbiQV, else the first skinned one.
  /// Checked by name first, because reading `MeshResource.contents` to look for the screen part
  /// is slow.
  private static func findModelEntity(in entity: Entity) -> ModelEntity? {
    func walk(_ e: Entity, _ matches: (ModelEntity) -> Bool) -> ModelEntity? {
      if let model = e as? ModelEntity, model.model != nil, matches(model) {
        return model
      }
      for child in e.children {
        if let model = walk(child, matches) {
          return model
        }
      }
      return nil
    }
    return walk(entity) { $0.name == Rig.modelEntityName } ?? walk(entity) { !$0.jointNames.isEmpty }
  }

  private static func findClip(named name: String, in entity: Entity) -> (Entity, AnimationResource)? {
    if let clip = entity.components[AnimationLibraryComponent.self]?.animations[name] {
      return (entity, clip)
    }
    for child in entity.children {
      if let found = findClip(named: name, in: child) {
        return found
      }
    }
    return nil
  }

  /// Unwraps `AnimationView.source` and `AnimationGroup.group` down to the
  /// `SampledAnimation<JointTransforms>`, as DeviceHub's fn 1610 does. In V68.usdz the nested
  /// views and groups add no trim or offset of their own.
  private static func leafJointAnimation(in definition: any AnimationDefinition) -> SampledAnimation<JointTransforms>? {
    if let sampled = definition as? SampledAnimation<JointTransforms> {
      return sampled
    }
    if let view = definition as? AnimationView, let source = view.source {
      return leafJointAnimation(in: source)
    }
    if let group = definition as? AnimationGroup {
      for child in group.group {
        if let sampled = leafJointAnimation(in: child) {
          return sampled
        }
      }
    }
    return nil
  }

  // MARK: - Hinge

  private func sanitized(_ degrees: Double) -> Double {
    degrees.isFinite ? min(max(degrees, 0), 180) : hingeAngleDegrees
  }

  /// The clip time DeviceHub uses for an angle. ModelScene.applyHinge sets
  /// `controller.time = (open + (closed - open) × (1 - deg/180)) × definition.duration`, with open
  /// 0 and closed 0.923. The angle is clamped to 0...180; a non-finite one uses the current angle.
  public func foldClipTime(forAngleDegrees degrees: Double) -> TimeInterval {
    let progress = sanitized(degrees) / 180
    return (Rig.openClipProgress + (Rig.closedClipProgress - Rig.openClipProgress) * (1 - progress)) * foldClipDuration
  }

  /// Poses the model at a commanded angle (CMAngle): 0 closed, 180 flat, clamped to 0...180 as
  /// DeviceHub's setHinge does. Non-finite values, such as NaN from a degenerate gesture or a
  /// corrupt datagram, are ignored.
  public func setHinge(angleDegrees: Double) {
    guard angleDegrees.isFinite else {
      return
    }
    hingeAngleDegrees = min(max(angleDegrees, 0), 180)
    spring.value = hingeAngleDegrees
    spring.target = hingeAngleDegrees
    spring.velocity = 0
    hasInitializedHinge = true
    applyPose()
  }

  /// Re-applies the current angle. With `.playbackController`, call it once after adding `root`
  /// to a scene.
  public func applyPose() {
    let t = foldClipTime(forAngleDegrees: hingeAngleDegrees)
    switch driver {
    case .sampledJoints:
      applySampledJoints(clipTime: t)
    case .playbackController:
      if controller?.isValid != true, clipEntity.isActive {
        controller = clipEntity.playAnimation(foldClip, transitionDuration: 0, startsPaused: true)
        controller?.speed = 0
      }
      controller?.time = t
      syncScreenJoints()
    }
    foldFrame.transform = anchorTransform(angleDegrees: hingeAngleDegrees)
    updateClosedBlanking()
  }

  private func applySampledJoints(clipTime t: Double) {
    // An index into `frames`.
    var f = (foldClipStart + t - sampledStart) / frameInterval
    guard f.isFinite, !frames.isEmpty else {
      return
    }
    if abs(f - f.rounded()) < 1e-4 {
      f = f.rounded()
    }
    let i0 = min(max(Int(f.rounded(.down)), 0), frames.count - 1)
    let i1 = min(i0 + 1, frames.count - 1)
    let a = Float(min(max(f - Double(i0), 0), 1))
    var joints = modelEntity.jointTransforms
    for (k, modelJoint) in sampledToModelJoint.enumerated() {
      let p = frames[i0][k]
      let q = frames[i1][k]
      joints[modelJoint] = a == 0
        ? p
        : Transform(
          scale: simd_mix(p.scale, q.scale, SIMD3(repeating: a)),
          rotation: simd_slerp(p.rotation, q.rotation, a),
          translation: simd_mix(p.translation, q.translation, SIMD3(repeating: a))
        )
    }
    modelEntity.jointTransforms = joints
    syncScreenJoints()
  }

  /// Copies the body's joint transforms to the separate screen entities. `applyPose` does it for
  /// the sampled driver; with `.playbackController`, call it after the scene has evaluated the
  /// clip, or the screens lag.
  public func syncScreenJoints() {
    guard !screenEntities.isEmpty else {
      return
    }
    let joints = modelEntity.jointTransforms
    for entity in screenEntities.values {
      entity.jointTransforms = joints
    }
  }

  /// foldFrame's transform for an angle under the current anchor. `book_close` turns the camera
  /// leaf by +phi/2 and the cover leaf by -phi/2 about +Z (phi = 180 - angle); the anchors undo
  /// one of them about the hinge line.
  public func anchorTransform(angleDegrees degrees: Double) -> Transform {
    let d = sanitized(degrees)
    let phi = Float((180 - d) * .pi / 180)
    func aboutHinge(_ angle: Float) -> Transform {
      let rotation = simd_quatf(angle: angle, axis: hingeAxis)
      return Transform(scale: .one, rotation: rotation, translation: hingePoint - rotation.act(hingePoint))
    }
    switch anchor {
    case .deviceHub:
      return Transform(translation: -centeringOffset * Float(1 - d / 180))
    case .hinge:
      return .identity
    case .coverLeaf:
      return aboutHinge(phi / 2)
    case .cameraLeaf:
      return aboutHinge(-phi / 2)
    }
  }

  /// The hinge line in root space for the current anchor and angle. It stays at `hingePoint` for
  /// every anchor except `.deviceHub`, which moves it by -(0, 42.8 mm, 0) × (1 - angle/180).
  public var hingeLine: (point: SIMD3<Float>, axis: SIMD3<Float>) {
    let matrix = foldFrame.transform.matrix
    let p = matrix * SIMD4<Float>(hingePoint, 1)
    let a = matrix * SIMD4<Float>(hingeAxis, 0)
    return (SIMD3(p.x, p.y, p.z), normalize(SIMD3(a.x, a.y, a.z)))
  }

  /// Sets the spring's target, as DeviceHub's setHinge does; call `update(deltaTime:)` every frame.
  ///
  /// The first target of a model never posed with `setHinge` snaps, as DeviceHub's
  /// hasInitializedHinge does, so a client that learns the real angle on connect does not animate
  /// from flat. After any `setHinge` it springs.
  public func setHingeTarget(angleDegrees: Double) {
    guard angleDegrees.isFinite else {
      return
    }
    guard hasInitializedHinge else {
      setHinge(angleDegrees: angleDegrees)
      return
    }
    spring.target = min(max(angleDegrees, 0), 180)
  }

  /// Steps the spring and poses the model. Returns false once settled.
  @discardableResult
  public func update(deltaTime: Double) -> Bool {
    guard !spring.isSettled, deltaTime.isFinite else {
      return !spring.isSettled
    }
    spring.step(deltaTime)
    guard spring.value.isFinite else {
      spring.value = hingeAngleDegrees
      spring.velocity = 0
      return false
    }
    hingeAngleDegrees = spring.value
    applyPose()
    return !spring.isSettled
  }

  // MARK: - Screens

  /// Puts a material on a display.
  ///
  /// With `.separateEntities` it replaces the screen entity's only material; with `.inPlace`, the
  /// display's slots in the body. While the hinge is closed the inner screen keeps showing black
  /// (`blankInnerWhenClosed`), and gets this material back when it opens.
  public func setMaterial(_ material: any Material, for display: Display) {
    clientMaterials[display] = material
    applyScreenMaterial(display)
  }

  /// Puts a texture on a display, as an UnlitMaterial without tone mapping: the default tone map
  /// darkens 255 to 213.
  public func setTexture(_ texture: TextureResource, for display: Display) {
    var material = UnlitMaterial(applyPostProcessToneMap: false)
    material.color = .init(tint: .white, texture: .init(texture))
    setMaterial(material, for: display)
  }

  func applyScreenMaterial(_ display: Display) {
    let chosen: (any Material)?
    if display == .inner && isInnerBlanked {
      chosen = blackMaterial
    } else {
      chosen = clientMaterials[display] ?? fileMaterials[display]
    }
    guard let material = chosen else {
      return
    }
    if let entity = screenEntities[display] {
      entity.model?.materials = [material]
      return
    }
    guard var modelComponent = modelEntity.model else {
      return
    }
    for i in slots[display] ?? [] where i < modelComponent.materials.count {
      modelComponent.materials[i] = material
    }
    modelEntity.model = modelComponent
  }

  private func updateClosedBlanking() {
    let closed = blankInnerWhenClosed && hingeAngleDegrees <= Rig.closedHingeEpsilon
    guard closed != isInnerBlanked else {
      return
    }
    isInnerBlanked = closed
    applyScreenMaterial(.inner)
  }
}
