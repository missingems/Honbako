import CoreGraphics

enum HonbakoJapaneseWordGeometry {
    /// A whole-line box repeated for several words is not a word anchor. Keep
    /// the word in the model, but let the interface use its unanchored list.
    static func validated(
        _ words: [HonbakoJapaneseWordRegion],
        in parentBox: CGRect
    ) -> [HonbakoJapaneseWordRegion] {
        let clipped = words.map { item -> HonbakoJapaneseWordRegion in
            guard let box = item.boundingBox,
                  let imageBox = HonbakoJapaneseGeometry.rect(for: box, in: CGRect(x: 0, y: 0, width: 1, height: 1)) else {
                return .init(word: item.word, boundingBox: nil)
            }
            let intersection = imageBox.intersection(parentBox)
            guard !intersection.isNull, !intersection.isEmpty,
                  intersection.width * intersection.height >= box.width * box.height * 0.9 else {
                return .init(word: item.word, boundingBox: nil)
            }
            return .init(word: item.word, boundingBox: intersection)
        }
        guard words.count > 1 else { return clipped }
        return clipped.map { item in
            guard let box = item.boundingBox,
                  !nearlyEqual(box, parentBox),
                  !clipped.contains(where: { other in
                      other.id != item.id && other.boundingBox.map { nearlyEqual(box, $0) } == true
                  }) else { return .init(word: item.word, boundingBox: nil) }
            return item
        }
    }

    /// A recognizer can expose accurate character boxes even when its
    /// word-range API repeats the entire vertical column. Only union real,
    /// distinct character rectangles; never divide a phrase proportionally.
    static func characterUnion(_ boxes: [CGRect], in parentBox: CGRect) -> CGRect? {
        guard !boxes.isEmpty else { return nil }
        let imageBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        var clipped: [CGRect] = []
        for box in boxes {
            guard let normalized = HonbakoJapaneseGeometry.rect(for: box, in: imageBounds),
                  !nearlyEqual(normalized, parentBox) else { return nil }
            let intersection = normalized.intersection(parentBox)
            guard !intersection.isNull, !intersection.isEmpty,
                  intersection.width * intersection.height >= box.width * box.height * 0.9,
                  !clipped.contains(where: { nearlyEqual(intersection, $0) }) else { return nil }
            clipped.append(intersection)
        }
        return clipped.dropFirst().reduce(clipped[0]) { $0.union($1) }
    }

    private static func nearlyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance: CGFloat = 0.0005
        return abs(lhs.minX - rhs.minX) < tolerance && abs(lhs.minY - rhs.minY) < tolerance
            && abs(lhs.maxX - rhs.maxX) < tolerance && abs(lhs.maxY - rhs.maxY) < tolerance
    }
}
