import CoreGraphics

/// The guide uses top-left normalized coordinates, independent of image pixels or view scale.
enum HonbakoJapaneseGeometry {
    static func rect(for boundingBox: CGRect, in imageFrame: CGRect) -> CGRect? {
        guard valid(boundingBox), valid(imageFrame) else { return nil }
        let clipped = boundingBox.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard valid(clipped) else { return nil }
        return CGRect(
            x: imageFrame.minX + clipped.minX * imageFrame.width,
            y: imageFrame.minY + clipped.minY * imageFrame.height,
            width: clipped.width * imageFrame.width,
            height: clipped.height * imageFrame.height
        )
    }

    static func topLeftBox(fromVision boundingBox: CGRect) -> CGRect? {
        guard valid(boundingBox) else { return nil }
        let topLeft = CGRect(
            x: boundingBox.minX,
            y: 1 - boundingBox.maxY,
            width: boundingBox.width,
            height: boundingBox.height
        )
        return rect(for: topLeft, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Some Vision revisions recognize vertical Japanese but leave textDirection unset.
    /// Use image pixels rather than normalized aspect ratio so landscape pages stay correct.
    static func inferredDirection(
        for boundingBox: CGRect,
        imageSize: CGSize,
        characterCount: Int
    ) -> HonbakoJapaneseRegion.Direction {
        guard valid(boundingBox), characterCount > 1,
              imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0 else { return .unknown }
        let width = boundingBox.width * imageSize.width
        let height = boundingBox.height * imageSize.height
        if height > width * 1.4 { return .vertical }
        if width > height * 1.4 { return .horizontal }
        return .unknown
    }

    /// Some Vision revisions report left-to-right for a clearly vertical
    /// Japanese column. Resolve against the oriented page pixels, not the
    /// screen or normalized rectangle's aspect ratio.
    static func resolvedDirection(
        _ observed: HonbakoJapaneseRegion.Direction,
        for boundingBox: CGRect,
        imageSize: CGSize,
        characterCount: Int
    ) -> HonbakoJapaneseRegion.Direction {
        let inferred = inferredDirection(for: boundingBox, imageSize: imageSize, characterCount: characterCount)
        if observed == .vertical || inferred == .vertical { return .vertical }
        return observed == .unknown ? inferred : observed
    }

    private static func valid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0 && !rect.isNull && !rect.isInfinite
    }
}
