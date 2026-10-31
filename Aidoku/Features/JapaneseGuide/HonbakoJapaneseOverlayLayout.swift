#if SUMI
import CoreGraphics

/// Floating reading aids never cover a detected text box or another chip.
enum HonbakoJapaneseOverlayLayout {
    static func chipFrame(
        for textBox: CGRect,
        in imageBounds: CGRect,
        size: CGSize,
        spacing: CGFloat = 4,
        avoiding occupiedFrames: [CGRect] = []
    ) -> CGRect? {
        let values = [textBox.minX, textBox.minY, textBox.width, textBox.height,
                      imageBounds.minX, imageBounds.minY, imageBounds.width, imageBounds.height,
                      size.width, size.height, spacing]
        guard values.allSatisfy(\.isFinite), !textBox.isEmpty, !imageBounds.isEmpty,
              size.width > 0, size.height > 0, size.height <= imageBounds.height else { return nil }
        let box = textBox.intersection(imageBounds)
        guard !box.isNull, !box.isEmpty else { return nil }
        let width = min(size.width, imageBounds.width)
        let gap = max(0, spacing)
        let proposedX = [box.minX, box.midX - width / 2, box.maxX - width]
        let proposedY = [box.minY - gap - size.height, box.maxY + gap]
        for y in proposedY {
            guard y >= imageBounds.minY, y + size.height <= imageBounds.maxY else { continue }
            for x in proposedX {
                let clampedX = min(max(x, imageBounds.minX), imageBounds.maxX - width)
                let candidate = CGRect(x: clampedX, y: y, width: width, height: size.height)
                guard !candidate.intersects(box), !occupiedFrames.contains(where: candidate.intersects) else { continue }
                return candidate
            }
        }
        return nil
    }

    /// Word labels use measured text widths: a long word is omitted instead of truncated.
    static func wordChipFrame(
        for textBox: CGRect,
        in imageBounds: CGRect,
        size: CGSize,
        direction: HonbakoJapaneseRegion.Direction,
        containingTextBox: CGRect? = nil,
        side: HonbakoJapaneseOverlaySide? = nil,
        spacing: CGFloat = 4,
        avoiding occupiedFrames: [CGRect] = []
    ) -> CGRect? {
        let values = [textBox.minX, textBox.minY, textBox.width, textBox.height,
                      imageBounds.minX, imageBounds.minY, imageBounds.width, imageBounds.height,
                      size.width, size.height, spacing]
        guard values.allSatisfy(\.isFinite), !textBox.isEmpty, !imageBounds.isEmpty,
              size.width > 0, size.height > 0,
              size.width <= imageBounds.width, size.height <= imageBounds.height else { return nil }
        let box = textBox.intersection(imageBounds)
        guard !box.isNull, !box.isEmpty else { return nil }
        let gap = max(0, spacing)
        // Glyph ascenders vary within a line. Clear the whole line or column,
        // while keeping each label centered on its genuine word anchor.
        let clearance = containingTextBox?.intersection(imageBounds).union(box) ?? box
        let vertical = direction == .vertical
        let before = vertical ? clearance.minX - gap - size.width : clearance.minY - gap - size.height
        let after = vertical ? clearance.maxX + gap : clearance.maxY + gap
        let major: [CGFloat]
        switch side {
            case .before: major = [before]
            case .after: major = [after]
            case nil: major = vertical ? [after, before] : [before, after]
        }
        let minor = vertical
            ? [box.midY - size.height / 2]
            : [box.midX - size.width / 2]
        for first in major {
            for second in minor {
                let x = vertical ? first : min(max(second, imageBounds.minX), imageBounds.maxX - size.width)
                let y = vertical ? min(max(second, imageBounds.minY), imageBounds.maxY - size.height) : first
                let candidate = CGRect(origin: CGPoint(x: x, y: y), size: size)
                guard imageBounds.contains(candidate), !candidate.intersects(box),
                      !occupiedFrames.contains(where: candidate.intersects) else { continue }
                return candidate
            }
        }
        return nil
    }

    /// Vision can return the whole line for several ranges. Such overlapping
    /// anchors cannot truthfully locate separate words, so they stay in the list.
    static func distinctWordFrames(_ frames: [Int: CGRect]) -> [Int: CGRect] {
        frames.filter { identifier, frame in
            !frames.contains { otherID, other in
                guard otherID != identifier else { return false }
                let overlap = frame.intersection(other)
                guard !overlap.isNull, !overlap.isEmpty else { return false }
                let smallerArea = min(frame.width * frame.height, other.width * other.height)
                return smallerArea > 0 && overlap.width * overlap.height / smallerArea > 0.8
            }
        }
    }

}
#endif
