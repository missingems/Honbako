import simd

/// How the file's screen UVs relate to the simulator's native framebuffers.
///
/// The cover's UVs are its native framebuffer, unrotated: u = x/1398, v = 1 - y/2034. The inner
/// screen's are the upright 2853×2007 book image, turned 90° against the native 2007×2853 frame:
/// native y runs across the fold, native x along the hinge. RealityKit samples texture row 0 at
/// v = 1, so a texture made from a native framebuffer (row 0 first) is sampled at
/// (x/W, 1 - y/H).
extension DuoModel {
  /// The texture coordinate to write into the mesh at a vertex whose file UV is `uv`, so that a
  /// texture made from the native framebuffer shows the right pixel there.
  public nonisolated static func textureUV(
    forModelUV uv: SIMD2<Float>,
    on display: Display,
    mapping: InnerMapping
  ) -> SIMD2<Float> {
    guard display == .inner else {
      return uv
    }
    switch mapping {
    case .native:
      // x/2007 = 1 - v, 1 - y/2853 = u
      return SIMD2(1 - uv.y, uv.x)
    case .nativeRotated180:
      // x/2007 = v, 1 - y/2853 = 1 - u
      return SIMD2(uv.y, 1 - uv.x)
    case .upright:
      return uv
    }
  }

  /// The native framebuffer pixel (x right, y down, in pixels) shown at a file UV. For `.upright`
  /// it is the pixel of the 2853×2007 upright image instead.
  public nonisolated static func nativePixel(
    forModelUV uv: SIMD2<Double>,
    on display: Display,
    mapping: InnerMapping
  ) -> SIMD2<Double> {
    let size = display.framebufferSize
    let w = Double(size.x)
    let h = Double(size.y)
    guard display == .inner else {
      return SIMD2(uv.x * w, (1 - uv.y) * h)
    }
    switch mapping {
    case .native:
      return SIMD2((1 - uv.y) * w, (1 - uv.x) * h)
    case .nativeRotated180:
      return SIMD2(uv.y * w, uv.x * h)
    case .upright:
      return SIMD2(uv.x * h, (1 - uv.y) * w)
    }
  }

  /// The inverse of `nativePixel(forModelUV:on:mapping:)`.
  public nonisolated static func modelUV(
    forNativePixel p: SIMD2<Double>,
    on display: Display,
    mapping: InnerMapping
  ) -> SIMD2<Double> {
    let size = display.framebufferSize
    let w = Double(size.x)
    let h = Double(size.y)
    guard display == .inner else {
      return SIMD2(p.x / w, 1 - p.y / h)
    }
    switch mapping {
    case .native:
      return SIMD2(1 - p.y / h, 1 - p.x / w)
    case .nativeRotated180:
      return SIMD2(p.y / h, p.x / w)
    case .upright:
      return SIMD2(p.x / h, 1 - p.y / w)
    }
  }
}
