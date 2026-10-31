import RealityKit
import simd

extension DuoModel {
  /// The posed screens, and on request the posed body, in root space.
  ///
  /// Cached until the joints or the anchor transform change. It reads the body's current joint
  /// transforms, so it works with either driver.
  func currentPose(includeBody: Bool) -> PoseCache {
    let joints = modelEntity.jointTransforms
    let toRoot = modelEntity.transformMatrix(relativeTo: root)
    var pose: PoseCache
    if let cached = poseCache, cached.toRoot == toRoot, Self.sameJoints(cached.joints, joints) {
      pose = cached
    } else {
      let skin = skinMatrices(joints)
      var screens: [Display: [SIMD3<Float>]] = [:]
      for (display, mesh) in screenMeshes {
        screens[display] = Self.skin(
          mesh.positions, mesh.influences, mesh.influencesPerVertex, rigid: nil, skin, toRoot
        )
      }
      pose = PoseCache(joints: joints, toRoot: toRoot, skin: skin, screens: screens, body: nil, bodyBoxes: nil)
    }
    if includeBody, pose.body == nil {
      var body: [[SIMD3<Float>]] = []
      var boxes: [(SIMD3<Float>, SIMD3<Float>)] = []
      body.reserveCapacity(bodyParts.count)
      boxes.reserveCapacity(bodyParts.count)
      for part in bodyParts {
        let posed = Self.skin(
          part.positions, part.influences, part.influencesPerVertex, rigid: part.rigidJoint, pose.skin, toRoot
        )
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = -lo
        for v in posed {
          lo = simd_min(lo, v)
          hi = simd_max(hi, v)
        }
        body.append(posed)
        boxes.append((lo, hi))
      }
      pose.body = body
      pose.bodyBoxes = boxes
    }
    poseCache = pose
    return pose
  }

  /// The posed screen mesh in root space (metres): positions, UVs in the file's convention (the
  /// camera trims' fitted to the cover) and triangles. The cover includes its camera trims when
  /// `coverCameraFill` is on.
  public func posedScreen(
    _ display: Display
  ) -> (positions: [SIMD3<Float>], modelUV: [SIMD2<Float>], triangles: [UInt32])? {
    guard let mesh = screenMeshes[display], let positions = currentPose(includeBody: false).screens[display] else {
      return nil
    }
    return (positions, mesh.modelUV, mesh.triangles)
  }

  /// Axis-aligned bounds of the posed model, body and screens, in root space. Use it instead of
  /// `visualBounds`, which RealityKit keeps at the bind (flat) pose.
  public func posedBounds() -> BoundingBox {
    let pose = currentPose(includeBody: true)
    var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
    var hi = -lo
    for (a, b) in pose.bodyBoxes ?? [] {
      lo = simd_min(lo, a)
      hi = simd_max(hi, b)
    }
    for positions in pose.screens.values {
      for v in positions {
        lo = simd_min(lo, v)
        hi = simd_max(hi, v)
      }
    }
    return BoundingBox(min: lo, max: hi)
  }

  /// The rigid transform, in root space, that takes a point given in the flat, unanchored rest
  /// frame (the model at 180° with the `.hinge` anchor, which is its bind pose) to where that point
  /// of the leaf is now.
  ///
  /// Parent box colliders or a hinge handle to an entity with this transform to make them follow
  /// the leaf.
  public func leafTransform(_ leaf: Leaf) -> simd_float4x4 {
    let pose = currentPose(includeBody: false)
    guard let joint = leafJointIndex[leaf], joint < pose.skin.count else {
      return matrix_identity_float4x4
    }
    return pose.toRoot * pose.skin[joint] * restModelToRoot.inverse
  }

  /// Bounds of a leaf's rigid body parts in the flat rest frame (see `leafTransform(_:)`), screens
  /// excluded.
  public func restLeafBounds(_ leaf: Leaf) -> BoundingBox? {
    guard let joint = leafJointIndex[leaf] else {
      return nil
    }
    var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
    var hi = -lo
    var found = false
    for part in bodyParts where part.rigidJoint == joint {
      for v in part.positions {
        let r = restModelToRoot * SIMD4<Float>(v, 1)
        lo = simd_min(lo, SIMD3(r.x, r.y, r.z))
        hi = simd_max(hi, SIMD3(r.x, r.y, r.z))
        found = true
      }
    }
    return found ? BoundingBox(min: lo, max: hi) : nil
  }

  /// A static-mesh collision shape of the posed screen, in the screen entity's (the model
  /// entity's) local space.
  ///
  /// A mesh collider does not follow skinning and takes about 20 ms to build for the inner screen
  /// on a Mac, so rebuild it when the hinge settles (`update(deltaTime:)` returns false, or after
  /// `setHinge`), not every frame. Touches are held back during a fold anyway (spec §4.4).
  public func screenCollisionShape(for display: Display) async throws -> ShapeResource {
    guard let mesh = screenMeshes[display] else {
      throw LoadError(description: "no \(display) screen mesh")
    }
    let pose = currentPose(includeBody: false)
    let local = Self.skin(
      mesh.positions, mesh.influences, mesh.influencesPerVertex, rigid: nil, pose.skin, matrix_identity_float4x4
    )
    guard local.count <= Int(UInt16.max) else {
      throw LoadError(description: "screen mesh too large for UInt16 indices")
    }
    return try await ShapeResource.generateStaticMesh(positions: local, faceIndices: mesh.triangles.map { UInt16($0) })
  }
}
