import RealityKit

extension DuoModel {
  /// Every part's triangle index count is padded to a multiple of this.
  ///
  /// 24 indices are 48 bytes as UInt16 and 96 as UInt32, both multiples of 16, and a multiple of
  /// 3, so the padding is whole triangles.
  nonisolated static let indexCountAlignment = 24

  /// A copy of `contents` whose parts' triangle index counts are multiples of
  /// `indexCountAlignment`, padded with degenerate triangles.
  ///
  /// visionOS's render server crashes on a rebuilt mesh whose parts' index data does not start on
  /// a 16-byte boundary. A mesh made with `MeshResource(from:)` or `generate(from:)` goes to
  /// backboardd as one payload with every part's indices packed back to back, as UInt16 for these
  /// parts. backboardd's `IndexValidation._validate_neon` reads each part's indices as `SIMD8<UInt16>`
  /// (or `SIMD4<UInt32>`), and `MutableSpan(_unsafeBytes:)` traps on a base that is not 16-byte
  /// aligned. So the second part traps unless the first one's index bytes are a multiple of 16:
  /// V68's cover screen has 534 indices (1068 bytes) and the next part crashed backboardd (visionOS
  /// 27.0 simulator; `Research/probes/simmodel`). Meshes RealityKit loads from a file are packed
  /// differently and never crashed.
  ///
  /// Each degenerate triangle repeats the part's first index, so it has no area: the GPU draws
  /// nothing for it, and it costs at most 7 triangles a part. The CPU copies for hit testing and
  /// bounds are taken from the unpadded contents.
  nonisolated static func paddingIndicesToAlignment(_ contents: MeshResource.Contents) -> MeshResource.Contents {
    var padded = contents
    var models = Array(contents.models)
    var changed = false
    for m in models.indices {
      var parts = Array(models[m].parts)
      var partsChanged = false
      for p in parts.indices {
        guard let indices = parts[p].triangleIndices?.elements, let first = indices.first else {
          continue
        }
        let remainder = indices.count % indexCountAlignment
        guard remainder != 0 else {
          continue
        }
        let extra = repeatElement(first, count: indexCountAlignment - remainder)
        parts[p].triangleIndices = MeshBuffers.TriangleIndices(indices + extra)
        partsChanged = true
      }
      if partsChanged {
        models[m].parts = MeshPartCollection(parts)
        changed = true
      }
    }
    if changed {
      padded.models = MeshModelCollection(models)
    }
    return padded
  }
}
