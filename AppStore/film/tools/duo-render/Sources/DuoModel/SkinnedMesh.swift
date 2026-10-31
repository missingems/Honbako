import RealityKit
import simd

// The CPU copies of the screens and the body that DuoModel skins for hit testing, bounds and
// colliders. RealityKit skins on the GPU only and keeps `visualBounds` at the bind pose, so the
// posed geometry has to be computed here.

extension DuoModel {
  /// A joint influence. RealityKit's `MeshJointInfluence` is not Sendable, and the body's copy is
  /// read off the main actor.
  struct Influence: Sendable {
    static let none = Influence(joint: 0, weight: 0)

    var joint: Int32
    var weight: Float

    init(joint: Int32, weight: Float) {
      self.joint = joint
      self.weight = weight
    }

    init(_ influence: MeshJointInfluence) {
      joint = Int32(influence.jointIndex)
      weight = influence.weight
    }
  }

  /// A screen's bind-pose mesh, with the parts that share its material (the cover's camera trims).
  struct ScreenMesh {
    /// Bind pose, model units (cm).
    var positions: [SIMD3<Float>] = []
    /// The file's `primvars:st`; the fitted cover UVs for the camera trims.
    var modelUV: [SIMD2<Float>] = []
    var triangles: [UInt32] = []
    var influences: [Influence] = []
    var influencesPerVertex = 1
    var partIDs: [String] = []

    /// Appends another part, padding the influences so every vertex has the same count.
    mutating func append(
      id: String,
      positions newPositions: [SIMD3<Float>],
      uv: [SIMD2<Float>],
      triangles newTriangles: [UInt32],
      influences newInfluences: [Influence]
    ) {
      let perVertex = newPositions.isEmpty ? 1 : max(1, newInfluences.count / newPositions.count)
      let base = UInt32(positions.count)
      let target = max(influencesPerVertex, perVertex)
      if target > influencesPerVertex {
        influences = Self.pad(influences, from: influencesPerVertex, to: target)
      }
      let complete = newInfluences.count == newPositions.count * perVertex
        ? newInfluences
        : [Influence](repeating: .none, count: newPositions.count * perVertex)
      influences += Self.pad(complete, from: perVertex, to: target)
      influencesPerVertex = target
      positions += newPositions
      modelUV += uv
      triangles += newTriangles.map { $0 + base }
      partIDs.append(id)
    }

    static func pad(_ influences: [Influence], from a: Int, to b: Int) -> [Influence] {
      guard b > a, a > 0 else {
        return influences
      }
      var out: [Influence] = []
      out.reserveCapacity(influences.count / a * b)
      for vertex in 0..<(influences.count / a) {
        out += influences[(vertex * a)..<(vertex * a + a)]
        out += [Influence](repeating: .none, count: b - a)
      }
      return out
    }
  }

  /// One part of the body, for occlusion and bounds.
  struct BodyPart: Sendable {
    var id: String
    /// Bind pose, model units (cm).
    var positions: [SIMD3<Float>]
    /// Empty for transparent parts, which count for bounds only.
    var triangles: [UInt32]
    var influences: [Influence]
    var influencesPerVertex: Int
    /// Set when every vertex is fully on this joint.
    var rigidJoint: Int?
    /// Opaque parts block touches; transparent glass does not.
    var occludes: Bool
  }

  /// The posed geometry for one set of joint transforms and one anchor transform.
  struct PoseCache {
    var joints: [Transform]
    var toRoot: simd_float4x4
    var skin: [simd_float4x4]
    var screens: [Display: [SIMD3<Float>]]
    var body: [[SIMD3<Float>]]?
    var bodyBoxes: [(SIMD3<Float>, SIMD3<Float>)]?
  }

  struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
  }

  /// The prepared meshes: the body (with `.separateEntities`) or everything (`.inPlace`), and each
  /// screen's own.
  struct BuiltContents {
    var host: MeshResource.Contents
    var screens: [(Display, MeshResource.Contents)]
  }

  /// Skin matrices (model units) for the given local joint transforms:
  /// world(joint) × inverseBind(joint).
  func skinMatrices(_ local: [Transform]) -> [simd_float4x4] {
    var world = [simd_float4x4](repeating: matrix_identity_float4x4, count: local.count)
    for i in local.indices {
      let matrix = local[i].matrix
      world[i] = parentIndices[i].map { world[$0] * matrix } ?? matrix
    }
    return zip(world, inverseBind).map { $0 * $1 }
  }

  static func sameJoints(_ a: [Transform], _ b: [Transform]) -> Bool {
    guard a.count == b.count else {
      return false
    }
    for i in a.indices
    where a[i].translation != b[i].translation || a[i].rotation != b[i].rotation || a[i].scale != b[i].scale {
      return false
    }
    return true
  }

  /// Skins `positions` and maps them through `out`. A rigid part takes one matrix; a part with no
  /// influences stays at its bind position.
  static func skin(
    _ positions: [SIMD3<Float>],
    _ influences: [Influence],
    _ perVertex: Int,
    rigid: Int?,
    _ skin: [simd_float4x4],
    _ out: simd_float4x4
  ) -> [SIMD3<Float>] {
    if let joint = rigid ?? (perVertex == 0 ? -1 : nil) {
      let matrix = joint >= 0 ? out * skin[joint] : out
      return positions.map {
        let r = matrix * SIMD4<Float>($0, 1)
        return SIMD3(r.x, r.y, r.z)
      }
    }
    var result = [SIMD3<Float>](repeating: .zero, count: positions.count)
    for (vertex, position) in positions.enumerated() {
      var sum = SIMD4<Float>.zero
      var weights: Float = 0
      let p4 = SIMD4<Float>(position, 1)
      for j in 0..<perVertex {
        let influence = influences[vertex * perVertex + j]
        if influence.weight != 0 {
          sum += influence.weight * (skin[Int(influence.joint)] * p4)
          weights += influence.weight
        }
      }
      if weights == 0 {
        // An unskinned vertex keeps its bind position.
        sum = p4
      }
      let r = out * SIMD4<Float>(sum.x, sum.y, sum.z, 1)
      result[vertex] = SIMD3(r.x, r.y, r.z)
    }
    return result
  }
}
