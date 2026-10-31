import simd

extension DuoModel {
  public struct ScreenHit: Sendable {
    public var display: Display
    /// The native framebuffer pixel (x right, y down).
    public var pixel: SIMD2<Double>
    public var modelUV: SIMD2<Double>
    /// Root space, metres.
    public var position: SIMD3<Float>
    /// For `hitTest`, the distance along the ray from its origin, in metres, whatever the length
    /// of the direction. For `pixel(nearestTo:)`, the distance from the query point to the
    /// surface, in metres.
    public var distance: Float
  }

  /// The screen pixel a ray in root space lands on, or nil.
  ///
  /// The opaque body stops the ray, as it hides the screen in the GPU image: a screen hit is
  /// dropped when an opaque body part, or any screen seen from behind, is nearer. Transparent
  /// parts (the camera and back glass) do not stop it. The direction need not be normalised.
  public func hitTest(origin: SIMD3<Float>, direction: SIMD3<Float>) -> ScreenHit? {
    let length = simd_length(direction)
    guard length.isFinite, length > 0, origin.x.isFinite, origin.y.isFinite, origin.z.isFinite else {
      return nil
    }
    let dir = direction / length
    let pose = currentPose(includeBody: false)
    var best: ScreenHit?
    var nearestBack = Float.greatestFiniteMagnitude
    for display in Display.allCases {
      guard let mesh = screenMeshes[display], let positions = pose.screens[display] else {
        continue
      }
      let triangles = mesh.triangles
      let uv = mesh.modelUV
      for t in stride(from: 0, to: triangles.count, by: 3) {
        let ia = Int(triangles[t])
        let ib = Int(triangles[t + 1])
        let ic = Int(triangles[t + 2])
        // Möller–Trumbore.
        let a = positions[ia]
        let e1 = positions[ib] - a
        let e2 = positions[ic] - a
        let pv = cross(dir, e2)
        let det = dot(e1, pv)
        if abs(det) < 1e-14 {
          continue
        }
        let inverse = 1 / det
        let tv = origin - a
        let u = dot(tv, pv) * inverse
        if u < 0 || u > 1 {
          continue
        }
        let qv = cross(tv, e1)
        let v = dot(dir, qv) * inverse
        if v < 0 || u + v > 1 {
          continue
        }
        let distance = dot(e2, qv) * inverse
        if distance <= 0 {
          continue
        }
        // Screens wind counter-clockwise seen from the front, so a negative determinant is a
        // screen seen from behind: it hides whatever is beyond it.
        if det < 0 {
          nearestBack = min(nearestBack, distance)
          continue
        }
        if distance >= (best?.distance ?? .greatestFiniteMagnitude) {
          continue
        }
        let w = 1 - u - v
        let modelUV = SIMD2<Double>(w * uv[ia] + u * uv[ib] + v * uv[ic])
        best = ScreenHit(
          display: display,
          pixel: Self.nativePixel(forModelUV: modelUV, on: display, mapping: innerMapping),
          modelUV: modelUV,
          position: origin + distance * dir,
          distance: distance
        )
      }
    }
    guard let hit = best else {
      return nil
    }
    let limit = hit.distance - Rig.occlusionTolerance
    if nearestBack < limit {
      return nil
    }
    if bodyBlocks(origin: origin, direction: dir, before: limit) {
      return nil
    }
    return hit
  }

  /// Whether an opaque body triangle crosses the ray between its origin and `limit` metres.
  private func bodyBlocks(origin o: SIMD3<Float>, direction dir: SIMD3<Float>, before limit: Float) -> Bool {
    guard limit > 0 else {
      return false
    }
    let pose = currentPose(includeBody: true)
    guard let body = pose.body, let boxes = pose.bodyBoxes else {
      return false
    }
    let inverseDir = SIMD3<Float>(1 / dir.x, 1 / dir.y, 1 / dir.z)
    for (index, part) in bodyParts.enumerated() where part.occludes {
      // Slab test of the part's box against [0, limit].
      let (lo, hi) = boxes[index]
      let t1 = (lo - o) * inverseDir
      let t2 = (hi - o) * inverseDir
      let tmin = simd_reduce_max(simd_min(t1, t2))
      let tmax = simd_reduce_min(simd_max(t1, t2))
      if !(tmax >= max(tmin, 0)) || tmin > limit {
        continue
      }
      let positions = body[index]
      let triangles = part.triangles
      for t in stride(from: 0, to: triangles.count, by: 3) {
        let a = positions[Int(triangles[t])]
        let e1 = positions[Int(triangles[t + 1])] - a
        let e2 = positions[Int(triangles[t + 2])] - a
        let pv = cross(dir, e2)
        let det = dot(e1, pv)
        if abs(det) < 1e-20 {
          continue
        }
        let inverse = 1 / det
        let tv = o - a
        let u = dot(tv, pv) * inverse
        if u < 0 || u > 1 {
          continue
        }
        let qv = cross(tv, e1)
        let v = dot(dir, qv) * inverse
        if v < 0 || u + v > 1 {
          continue
        }
        let distance = dot(e2, qv) * inverse
        if distance > 0 && distance < limit {
          return true
        }
      }
    }
    return false
  }

  /// The screen pixel nearest to a point in root space, within `maxDistance` metres of the posed
  /// surface: for a direct touch, its `location3D` converted with
  /// `entity.convert(position:to: duo.root)`.
  ///
  /// There is no occlusion test, so pass the display the gesture began on.
  public func pixel(nearestTo point: SIMD3<Float>, on display: Display? = nil, maxDistance: Float = 0.005) -> ScreenHit? {
    guard point.x.isFinite, point.y.isFinite, point.z.isFinite else {
      return nil
    }
    let pose = currentPose(includeBody: false)
    var best: ScreenHit?
    for candidate in Display.allCases where display == nil || display == candidate {
      guard let mesh = screenMeshes[candidate], let positions = pose.screens[candidate] else {
        continue
      }
      let triangles = mesh.triangles
      let uv = mesh.modelUV
      for t in stride(from: 0, to: triangles.count, by: 3) {
        let ia = Int(triangles[t])
        let ib = Int(triangles[t + 1])
        let ic = Int(triangles[t + 2])
        let (q, weights) = Self.closestPoint(point, positions[ia], positions[ib], positions[ic])
        let distance = simd_length(point - q)
        if distance > maxDistance || distance >= (best?.distance ?? .greatestFiniteMagnitude) {
          continue
        }
        let modelUV = SIMD2<Double>(weights.x * uv[ia] + weights.y * uv[ib] + weights.z * uv[ic])
        best = ScreenHit(
          display: candidate,
          pixel: Self.nativePixel(forModelUV: modelUV, on: candidate, mapping: innerMapping),
          modelUV: modelUV,
          position: q,
          distance: distance
        )
      }
    }
    return best
  }

  /// The closest point on triangle abc to p, with its barycentric weights (Ericson, Real-Time
  /// Collision Detection, 5.1.5).
  ///
  /// In Double: the crease band's triangles are 0.66 × 110 mm slivers, where Float loses about
  /// 0.03 mm.
  private nonisolated static func closestPoint(
    _ pf: SIMD3<Float>,
    _ af: SIMD3<Float>,
    _ bf: SIMD3<Float>,
    _ cf: SIMD3<Float>
  ) -> (SIMD3<Float>, SIMD3<Float>) {
    let a = SIMD3<Double>(af)
    let b = SIMD3<Double>(bf)
    let c = SIMD3<Double>(cf)
    let p = SIMD3<Double>(pf)
    func out(_ w: SIMD3<Double>) -> (SIMD3<Float>, SIMD3<Float>) {
      (SIMD3<Float>(w.x * a + w.y * b + w.z * c), SIMD3<Float>(w))
    }
    let ab = b - a
    let ac = c - a
    let ap = p - a
    let d1 = dot(ab, ap)
    let d2 = dot(ac, ap)
    if d1 <= 0 && d2 <= 0 {
      return out([1, 0, 0])
    }
    let bp = p - b
    let d3 = dot(ab, bp)
    let d4 = dot(ac, bp)
    if d3 >= 0 && d4 <= d3 {
      return out([0, 1, 0])
    }
    let vc = d1 * d4 - d3 * d2
    if vc <= 0 && d1 >= 0 && d3 <= 0 {
      let v = d1 / (d1 - d3)
      return out([1 - v, v, 0])
    }
    let cp = p - c
    let d5 = dot(ab, cp)
    let d6 = dot(ac, cp)
    if d6 >= 0 && d5 <= d6 {
      return out([0, 0, 1])
    }
    let vb = d5 * d2 - d1 * d6
    if vb <= 0 && d2 >= 0 && d6 <= 0 {
      let w = d2 / (d2 - d6)
      return out([1 - w, 0, w])
    }
    let va = d3 * d6 - d5 * d4
    if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 {
      let w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
      return out([0, 1 - w, w])
    }
    let denominator = 1 / (va + vb + vc)
    let v = vb * denominator
    let w = vc * denominator
    return out([1 - v - w, v, w])
  }

  /// Where a native framebuffer pixel sits on the posed model, in root space. nil outside the
  /// screen mesh.
  public func position(ofPixel p: SIMD2<Double>, on display: Display) -> SIMD3<Float>? {
    guard p.x.isFinite, p.y.isFinite, let (positions, uv, triangles) = posedScreen(display) else {
      return nil
    }
    let target = SIMD2<Float>(Self.modelUV(forNativePixel: p, on: display, mapping: innerMapping))
    for t in stride(from: 0, to: triangles.count, by: 3) {
      let ia = Int(triangles[t])
      let ib = Int(triangles[t + 1])
      let ic = Int(triangles[t + 2])
      let a = uv[ia]
      let b = uv[ib]
      let c = uv[ic]
      let d = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
      if abs(d) < 1e-12 {
        continue
      }
      let l1 = ((b.y - c.y) * (target.x - c.x) + (c.x - b.x) * (target.y - c.y)) / d
      let l2 = ((c.y - a.y) * (target.x - c.x) + (a.x - c.x) * (target.y - c.y)) / d
      let l3 = 1 - l1 - l2
      let tolerance: Float = -1e-5
      if l1 >= tolerance && l2 >= tolerance && l3 >= tolerance {
        return l1 * positions[ia] + l2 * positions[ib] + l3 * positions[ic]
      }
    }
    return nil
  }
}
