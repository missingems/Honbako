import RealityKit

// The names and constants below were measured in V68.usdz and in DeviceHub's V68 plugin
// (CoreDevicePopDeviceKitExtension, Xcode 27.1). `Client/DeviceModels/V68.manifest.json` records
// them with the evidence, and `Research/probes/simmodel` holds the probes that found them.

extension DuoModel {
  public enum Display: String, CaseIterable, Sendable, Codable {
    /// LCD, screenID 1. Native framebuffer 1398×2034, rigid on the cover leaf's outer face.
    case cover
    /// LCD-1, screenID 3. Native framebuffer 2007×2853, one skinned mesh across both leaves and
    /// the crease.
    case inner

    public var framebufferSize: SIMD2<Int> {
      self == .cover ? SIMD2(1398, 2034) : SIMD2(2007, 2853)
    }

    /// The screen's mesh part (its USD mesh name).
    public var partID: String {
      self == .cover ? "zaWsadDZpWAUDAX" : "mQHVkATpIwJRVQx"
    }

    /// The screen's material in the file. DeviceHub finds its screen slots by these names.
    public var materialName: String {
      self == .cover ? "YqugYDOqMSOpqyA" : "CvyXbAGXoolRUYl"
    }
  }

  /// The two rigid leaves of the body.
  public enum Leaf: String, CaseIterable, Sendable, Codable {
    /// pXhjqgUFTJHRqSk: the cover, the cover camera and the cover-side inner half. Spec §3.3's
    /// LeafA.
    case cover
    /// mXxhFfVnnQRwgSU: the rear cameras, the buttons and the camera-side inner half. Spec §3.3's
    /// LeafB.
    case camera

    public var jointName: String {
      self == .cover ? Rig.coverLeafJoint : Rig.cameraLeafJoint
    }
  }

  /// Which part of the model stays still while the hinge moves. phi = 180 - angle.
  public enum FoldAnchor: String, Sendable, CaseIterable, Codable {
    /// The default. The camera leaf stays still (within 0.01 mm) and the cover leaf turns by
    /// R_z(-phi) about the hinge line, which stays at `hingePoint`. Spec §3.3: LeafB fixed,
    /// `HingePivot.orientation = quat(angle: pi - theta, axis: -Z)`. The same pose as the file's
    /// `l_over_r` clip.
    case cameraLeaf
    /// DeviceHub's view: `book_close` turns each leaf by phi/2 about the hinge line (camera leaf +,
    /// cover leaf -), and the body moves by -(0, 4.28 cm, 0) × (1 - angle/180), ModelScene's
    /// foldCenteringOffset. Closed, the body stands on its edge with the cover facing -X; DeviceHub
    /// turns it with orientation rotations DuoModel does not reproduce.
    case deviceHub
    /// `book_close` without the recentring: the hinge line stays still, both leaves turn phi/2.
    case hinge
    /// The cover leaf stays still and the camera leaf turns by R_z(+phi): the file's `r_over_l`
    /// clip. Closed, whoever faced the flat inner screen sees the rear cameras, not the cover.
    case coverLeaf
  }

  public enum PoseDriver: String, Sendable, Codable {
    /// The one to use. Writes `ModelEntity.jointTransforms` from `book_close`'s sampled frames
    /// (linear between frames, like the clip's own tween), and the screen entities in the same call.
    case sampledJoints
    /// For parity checks with DeviceHub only: plays `book_close` paused and sets the controller's
    /// time, DeviceHub's own method. The body takes the pose only when the scene next evaluates
    /// animation, so the separate screen entities lag until `syncScreenJoints()` runs after that.
    case playbackController
  }

  /// How a native framebuffer texture is laid onto the inner screen.
  public enum InnerMapping: String, Sendable, CaseIterable, Codable {
    /// The default, inferred from iOS's orientation facts and not yet checked with a pattern drawn
    /// by an app on LCD-1 (spec §9, open question 1): native (x, y) lands at model
    /// u = 1 - y/2853, v = 1 - x/2007. Native row 0 is on the camera leaf's outer edge, row 2853 on
    /// the cover leaf's, row 1426.5 on the hinge; column 0 runs along the top edge.
    case native
    /// The only other rotation the fold allows: u = y/2853, v = x/2007.
    case nativeRotated180
    /// No remap: the file's UVs, which expect the upright 2853×2007 book image (simctl's screenshot
    /// orientation with the body in portrait), row 0 at the top edge and column 0 on the cover leaf.
    case upright
  }

  /// Where the screen meshes live.
  public enum ScreenHosting: String, Sendable, Codable {
    /// Each screen (the cover with its camera trims, and the inner) moves out of the body into a
    /// skinned ModelEntity of its own that shares the skeleton, and DuoModel copies the joint
    /// transforms to it. Needed for VideoMaterial: in RealityRenderer on macOS 27, a VideoMaterial
    /// on one slot of the 33-material body hid every other part of the body, and two VideoMaterials
    /// on one entity both showed the last video enqueued.
    case separateEntities
    /// The screens stay in the body and their material slots are replaced, as DeviceHub does with
    /// its occlusion material. Fine for UnlitMaterial and other texture materials.
    case inPlace
  }

  public struct Options: Sendable {
    /// The file's "color" variant: "Light" (the file's default) or "Dark". nil loads the default.
    public var colorVariant: String?
    public var anchor: FoldAnchor
    public var driver: PoseDriver
    public var innerMapping: InnerMapping
    /// Move the two cover camera trims onto the cover's slot with UVs fitted to the cover, as
    /// DeviceHub does, so the camera ring shows the framebuffer's own camera disc (111 px at
    /// (1254, 143)). The trims then also belong to the cover for hit testing.
    public var coverCameraFill: Bool
    public var screenHosting: ScreenHosting
    /// Show black on the inner screen while the hinge is at or below `Rig.closedHingeEpsilon`. The
    /// real LCD-1 is black when closed, and a VideoMaterial would otherwise keep the last open frame
    /// in the closed seam.
    public var blankInnerWhenClosed: Bool

    public init(
      colorVariant: String? = nil,
      anchor: FoldAnchor = .cameraLeaf,
      driver: PoseDriver = .sampledJoints,
      innerMapping: InnerMapping = .native,
      coverCameraFill: Bool = true,
      screenHosting: ScreenHosting = .separateEntities,
      blankInnerWhenClosed: Bool = true
    ) {
      self.colorVariant = colorVariant
      self.anchor = anchor
      self.driver = driver
      self.innerMapping = innerMapping
      self.coverCameraFill = coverCameraFill
      self.screenHosting = screenHosting
      self.blankInnerWhenClosed = blankInnerWhenClosed
    }
  }

  public enum Rig {
    public static let modelEntityName = "DgmOwZEmClRbiQV"
    public static let foldClipName = "book_close"
    public static let coverLeafJoint = "pXhjqgUFTJHRqSk"
    public static let cameraLeafJoint = "mXxhFfVnnQRwgSU"
    public static let spineJoint = "SqQmdVsdXKAfqzC"
    public static let cameraTrimPartIDs = ["bmdskBnACQHmBns", "RkWvQgvhQdurxKV"]
    /// The hinge line in the model's own units (cm, skeleton space): through (0, 0.27545, 0)
    /// along +Z.
    public static let hingePointCM = SIMD3<Float>(0, 0.27545, 0)
    public static let hingeAxis = SIMD3<Float>(0, 0, 1)
    // DeviceHub's ModelScene constants, from the V68 plugin's disassembly.
    public static let openClipProgress = 0.0
    public static let closedClipProgress = 0.923
    public static let foldCenteringOffsetCM = SIMD3<Float>(0, 4.28, 0)
    public static let closedHingeEpsilon = 0.5
    /// A screen hit counts as occluded when a body surface, or a screen crossed from behind, is
    /// nearer than the hit by more than this, in metres.
    public static let occlusionTolerance: Float = 1e-5
  }

  public struct LoadError: Error, CustomStringConvertible {
    public let description: String
  }
}
