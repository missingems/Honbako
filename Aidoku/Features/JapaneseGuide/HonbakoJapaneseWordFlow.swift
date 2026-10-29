#if SUMI
import SwiftUI

/// Word pairs stay together as text size or the sheet width changes.
struct HonbakoJapaneseWordFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arranged(subviews, width: proposal.width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arranged(subviews, width: bounds.width)
        for (index, frame) in arrangement.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func arranged(_ subviews: Subviews, width proposedWidth: CGFloat?) -> (frames: [CGRect], size: CGSize) {
        let finiteWidth = proposedWidth.flatMap { $0.isFinite ? max(1, $0) : nil }
        let limit = finiteWidth ?? .greatestFiniteMagnitude
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let measured = subview.sizeThatFits(ProposedViewSize(width: finiteWidth, height: nil))
            let size = CGSize(width: min(limit, max(0, measured.width)), height: max(0, measured.height))
            if x > 0, x + size.width > limit {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (frames, CGSize(width: usedWidth, height: subviews.isEmpty ? 0 : y + rowHeight))
    }
}
#endif
