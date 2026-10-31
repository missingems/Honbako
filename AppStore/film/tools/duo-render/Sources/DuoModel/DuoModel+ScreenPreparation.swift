import RealityKit
import simd

extension DuoModel {
  /// The CPU copy of the body for occlusion and bounds: every part not on a screen slot, the
  /// transparent ones for bounds only.
  ///
  /// Reading mesh buffers is slow (about 40 ms for the body's 250,000 triangle indices), so `load`
  /// runs this off the main actor while the meshes are built.
  nonisolated static func extractBodyParts(
    from contents: MeshResource.Contents,
    screenSlots: Set<Int>,
    transparentSlots: Set<Int>
  ) -> [BodyPart] {
    var out: [BodyPart] = []
    for model in contents.models {
      for part in model.parts where !screenSlots.contains(part.materialIndex) {
        let transparent = transparentSlots.contains(part.materialIndex)
        let positions = part.positions.elements
        guard !positions.isEmpty else {
          continue
        }
        let influences = (part.jointInfluences?.influences.elements ?? []).map(Influence.init)
        let perVertex = influences.count / positions.count
        var rigid: Int?
        if perVertex >= 1, let first = influences.first?.joint {
          var isRigid = true
          for vertex in 0..<positions.count {
            var weight: Float = 0
            for j in 0..<perVertex {
              let influence = influences[vertex * perVertex + j]
              if influence.weight != 0 {
                if influence.joint != first {
                  isRigid = false
                  break
                }
                weight += influence.weight
              }
            }
            if !isRigid || abs(weight - 1) > 1e-4 {
              isRigid = false
              break
            }
          }
          if isRigid {
            rigid = Int(first)
          }
        }
        let triangles = transparent ? [] : (part.triangleIndices?.elements ?? [])
        out.append(BodyPart(
          id: part.id,
          positions: positions,
          triangles: triangles,
          influences: influences,
          influencesPerVertex: perVertex,
          rigidJoint: rigid,
          occludes: !transparent && !triangles.isEmpty
        ))
      }
    }
    return out
  }

  /// The CPU preparation: finds the screens and records their skinning data, rewrites the inner
  /// UVs, fits the cover and moves the camera trims onto its slot, then splits the meshes.
  func buildScreenContents(from original: MeshResource.Contents, coverCameraFill: Bool) throws -> BuiltContents {
    guard let modelComponent = modelEntity.model else {
      throw LoadError(description: "the body has no ModelComponent")
    }
    var contents = original
    var models = Array(contents.models)
    var coverSlot = -1
    var coverFit: UVFit?

    // The screens.
    for m in models.indices {
      var parts = Array(models[m].parts)
      var changed = false
      for p in parts.indices {
        guard let display = Display.allCases.first(where: { $0.partID == parts[p].id }) else {
          continue
        }
        var part = parts[p]
        guard let uv = part.textureCoordinates?.elements, let triangles = part.triangleIndices?.elements else {
          continue
        }
        let positions = part.positions.elements
        let influences = (part.jointInfluences?.influences.elements ?? []).map(Influence.init)
        var mesh = ScreenMesh()
        mesh.append(id: part.id, positions: positions, uv: uv, triangles: triangles, influences: influences)
        screenMeshes[display] = mesh
        if display == .inner {
          part.textureCoordinates = MeshBuffers.TextureCoordinates(
            uv.map { Self.textureUV(forModelUV: $0, on: .inner, mapping: innerMapping) }
          )
          changed = true
        } else {
          coverSlot = part.materialIndex
          let fit = Self.affineUVFit(positions: positions, uv: uv)
          coverFit = fit
          var worst: Float = 0
          for (q, t) in zip(positions, uv) {
            let error = (Self.applyFit(fit, q) - t) * SIMD2<Float>(Display.cover.framebufferSize)
            worst = max(worst, simd_length(error))
          }
          coverFitResidualPx = Double(worst)
        }
        parts[p] = part
      }
      if changed {
        models[m].parts = MeshPartCollection(parts)
      }
    }
    guard screenMeshes[.cover] != nil, screenMeshes[.inner] != nil else {
      throw LoadError(description: "screen parts \(Display.cover.partID) / \(Display.inner.partID) not found")
    }

    // DeviceHub's cover camera fill: the trims join the cover's slot and its CPU mesh.
    if coverCameraFill, coverSlot >= 0, let fit = coverFit {
      for m in models.indices {
        var parts = Array(models[m].parts)
        var changed = false
        for p in parts.indices where Rig.cameraTrimPartIDs.contains(parts[p].id) {
          let positions = parts[p].positions.elements
          var lo = positions[0]
          var hi = positions[0]
          for q in positions {
            lo = simd_min(lo, q)
            hi = simd_max(hi, q)
          }
          cameraTrimCentresPx[parts[p].id] = Self.nativePixel(
            forModelUV: SIMD2<Double>(Self.applyFit(fit, (lo + hi) / 2)), on: .cover, mapping: innerMapping
          )
          let fitted = positions.map { Self.applyFit(fit, $0) }
          parts[p].textureCoordinates = MeshBuffers.TextureCoordinates(fitted)
          parts[p].materialIndex = coverSlot
          screenMeshes[.cover]?.append(
            id: parts[p].id,
            positions: positions,
            uv: fitted,
            triangles: parts[p].triangleIndices?.elements ?? [],
            influences: (parts[p].jointInfluences?.influences.elements ?? []).map(Influence.init)
          )
          changed = true
        }
        if changed {
          models[m].parts = MeshPartCollection(parts)
        }
      }
    }
    contents.models = MeshModelCollection(models)

    // Slots by material name, as DeviceHub finds them, plus the part's own. RealityKit orders the
    // materials differently from one launch to the next.
    for display in Display.allCases {
      var found = Set<Int>()
      for (i, material) in modelComponent.materials.enumerated() where material.name == display.materialName {
        found.insert(i)
      }
      for model in contents.models {
        for part in model.parts where part.id == display.partID {
          found.insert(part.materialIndex)
        }
      }
      slots[display] = found.sorted()
      if let first = slots[display]?.first, first < modelComponent.materials.count {
        fileMaterials[display] = modelComponent.materials[first]
      }
    }
    screenSlotSet = Set(slots.values.flatMap { $0 })
    transparentSlotSet = Set(modelComponent.materials.indices.filter { i in
      if let material = modelComponent.materials[i] as? PhysicallyBasedMaterial, case .transparent = material.blending {
        return true
      }
      return false
    })
    poseCache = nil
    guard screenHosting == .separateEntities else {
      return BuiltContents(host: contents, screens: [])
    }

    // Every part on a screen slot (the screen, and the camera trims once they use the cover's
    // slot) goes into that screen's own skinned mesh, with the same skeleton and instances.
    var body = MeshResource.Contents()
    body.skeletons = contents.skeletons
    var bodyModels: [MeshResource.Model] = []
    var screenModels: [Display: [MeshResource.Model]] = [:]
    for model in contents.models {
      var kept: [MeshResource.Part] = []
      var moved: [Display: [MeshResource.Part]] = [:]
      for part in model.parts {
        if let display = Display.allCases.first(where: { slots[$0]?.contains(part.materialIndex) == true }) {
          var screenPart = part
          screenPart.materialIndex = 0
          moved[display, default: []].append(screenPart)
        } else {
          kept.append(part)
        }
      }
      if !kept.isEmpty {
        bodyModels.append(MeshResource.Model(id: model.id, parts: kept))
      }
      for (display, parts) in moved {
        screenModels[display, default: []].append(MeshResource.Model(id: model.id, parts: parts))
      }
    }
    body.models = MeshModelCollection(bodyModels)
    let bodyIDs = Set(bodyModels.map(\.id))
    body.instances = MeshInstanceCollection(contents.instances.filter { bodyIDs.contains($0.model) })
    var screens: [(Display, MeshResource.Contents)] = []
    for display in Display.allCases {
      guard let displayModels = screenModels[display] else {
        continue
      }
      var screen = MeshResource.Contents()
      screen.skeletons = contents.skeletons
      screen.models = MeshModelCollection(displayModels)
      let ids = Set(displayModels.map(\.id))
      screen.instances = MeshInstanceCollection(contents.instances.filter { ids.contains($0.model) })
      screens.append((display, screen))
    }
    return BuiltContents(host: body, screens: screens)
  }

  /// Puts the built meshes on the entities. They are new MeshResources, so a mesh shared with
  /// another load is left alone.
  func install(body: MeshResource, screens: [Display: MeshResource]) {
    guard var modelComponent = modelEntity.model else {
      return
    }
    let joints = modelEntity.jointTransforms
    modelComponent.mesh = body
    modelEntity.model = modelComponent
    for display in Display.allCases {
      guard let mesh = screens[display] else {
        continue
      }
      let entity = ModelEntity(mesh: mesh, materials: [fileMaterials[display] ?? blackMaterial])
      entity.name = "DuoScreen." + display.rawValue
      modelEntity.addChild(entity)
      screenEntities[display] = entity
    }
    if modelEntity.jointTransforms.count == joints.count {
      modelEntity.jointTransforms = joints
    }
    for display in Display.allCases {
      applyScreenMaterial(display)
    }
    syncScreenJoints()
    poseCache = nil
  }

  /// Two in-plane axes of a flat screen, and the coefficients of u and v over (a, b, 1).
  typealias UVFit = (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)

  /// The least-squares affine map from positions on a flat screen to its UVs. DeviceHub's fn 1104
  /// does the same for the camera trims.
  static func affineUVFit(positions p: [SIMD3<Float>], uv: [SIMD2<Float>]) -> UVFit {
    var lo = p[0]
    var hi = p[0]
    for q in p {
      lo = simd_min(lo, q)
      hi = simd_max(hi, q)
    }
    let extent = hi - lo
    // The thinnest axis is the normal; the other two span the plane.
    let normal = extent.x < extent.y && extent.x < extent.z ? 0 : (extent.y < extent.z ? 1 : 2)
    let e1: SIMD3<Float> = normal == 0 ? [0, 1, 0] : [1, 0, 0]
    let e2: SIMD3<Float> = normal == 2 ? [0, 1, 0] : [0, 0, 1]
    var ata = simd_double3x3(0)
    var atu = SIMD3<Double>.zero
    var atv = SIMD3<Double>.zero
    for (q, t) in zip(p, uv) {
      let r = SIMD3<Double>(Double(dot(q, e1)), Double(dot(q, e2)), 1)
      ata += simd_double3x3(columns: (r * r.x, r * r.y, r * r.z))
      atu += r * Double(t.x)
      atv += r * Double(t.y)
    }
    let inverse = ata.inverse
    let cu = inverse * atu
    let cv = inverse * atv
    return (e1, e2, SIMD3<Float>(cu), SIMD3<Float>(cv))
  }

  static func applyFit(_ fit: UVFit, _ q: SIMD3<Float>) -> SIMD2<Float> {
    let r = SIMD3<Float>(dot(q, fit.0), dot(q, fit.1), 1)
    return SIMD2(dot(fit.2, r), dot(fit.3, r))
  }
}
