#if SUMI
import UIKit

final class SumiFilmstripLayout: UICollectionViewLayout {
    private(set) var pitch = SumiScrubberMetrics.cellPitch(axis: .horizontal, usesPairedPages: false)

    @discardableResult
    func configure(axis: NSLayoutConstraint.Axis, usesPairedPages: Bool) -> Bool {
        let updated = SumiScrubberMetrics.cellPitch(axis: axis, usesPairedPages: usesPairedPages)
        guard updated != pitch else { return false }
        pitch = updated
        invalidateLayout()
        return true
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: CGFloat(collectionView?.numberOfItems(inSection: 0) ?? 0) * pitch, height: collectionView?.bounds.height ?? 48)
    }
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { true }
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let count = collectionView?.numberOfItems(inSection: 0) ?? 0
        guard count > 0 else { return [] }
        let first = max(0, Int(rect.minX / pitch) - 2)
        let last = min(count - 1, Int(rect.maxX / pitch) + 2)
        guard first <= last else { return [] }
        return (first...last).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
    }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let collectionView else { return nil }
        let item = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        let center = CGFloat(indexPath.item) * pitch + pitch / 2
        // Every preview stays on the same flat plane, including at the rail's
        // ends. The collection view alone clips items as they scroll away.
        let height = min(SumiScrubberMetrics.pageHeight + 4, max(1, collectionView.bounds.height - 8))
        item.frame = CGRect(x: center - pitch / 2, y: (collectionView.bounds.height - height) / 2, width: pitch, height: height)
        return item
    }
    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint) -> CGPoint {
        guard let collectionView else { return proposedContentOffset }
        let index = ((proposedContentOffset.x + collectionView.bounds.width / 2 - pitch / 2) / pitch).rounded()
        let maximum = max(-collectionView.contentInset.left, collectionViewContentSize.width - collectionView.bounds.width + collectionView.contentInset.right)
        return CGPoint(x: min(maximum, max(-collectionView.contentInset.left, index * pitch + pitch / 2 - collectionView.bounds.width / 2)), y: 0)
    }
}
#endif
