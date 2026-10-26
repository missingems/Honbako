@testable import Sumi
import Testing
import UIKit

@MainActor
struct SumiPreviewGeometryTests {
    private func descendants<T: UIView>(_ view: UIView, type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type: type) }
    }

    private func expectCentered(_ strip: UICollectionView, physicalIndex: Int) throws {
        let selected = try #require(strip.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: physicalIndex, section: 0)))
        // UIScrollView rounds its native offset to the display pixel grid.
        let halfPixel = 0.5 / max(1, strip.traitCollection.displayScale)
        #expect(abs(strip.bounds.midX - selected.center.x) <= halfPixel + 0.001)
    }

    @Test("Every filmstrip item stays flat and opaque as it crosses either edge")
    func flatRailEdges() throws {
        let scrubber = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 300, height: 48))
        scrubber.update(chapterKey: "flat", totalPages: 12, currentPage: 6)
        scrubber.layoutIfNeeded()
        let strip = try #require(descendants(scrubber, type: UICollectionView.self).first)
        for offset: CGFloat in [-90, 0, 37, 150, 300] {
            strip.contentOffset.x = offset
            for index in 0..<12 {
                let attributes = try #require(strip.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0)))
                #expect(CATransform3DIsIdentity(attributes.transform3D))
                #expect(attributes.alpha == 1)
                #expect(attributes.size == CGSize(width: 30, height: 40))
            }
        }
    }

    @Test("Preview spacing follows upright artwork rather than the old large fixed cell pitch")
    func tightSpacingInBothAxes() throws {
        for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
            for paired in [false, true] {
                let toolbar = SumiReaderToolbar()
                toolbar.axis = axis
                toolbar.frame = CGRect(origin: .zero, size: toolbar.preferredSize(availableLength: 420))
                let scrubber = SumiPageScrubber()
                toolbar.mount(scrubber)
                scrubber.update(chapterKey: "compact", totalPages: 6, currentPage: 3,
                    spreads: paired ? [[1, 2], [3, 4], [5, 6]] : nil)
                toolbar.layoutIfNeeded()
                let strip = try #require(descendants(scrubber, type: UICollectionView.self).first)
                strip.layoutIfNeeded()
                let flow = try #require(strip.collectionViewLayout as? SumiFilmstripLayout)
                let cells = strip.visibleCells.compactMap { $0 as? SumiPageThumbnailCell }
                #expect(!cells.isEmpty)
                for cell in cells {
                    cell.layoutIfNeeded()
                    let print = try #require(descendants(cell, type: SumiSpreadThumbnailView.self).first)
                    let extent = axis == .vertical ? print.bounds.height : print.bounds.width
                    #expect(flow.pitch - extent >= 4 && flow.pitch - extent < 5.1)
                }
            }
        }
    }

    @Test("Loaded art and loading paper share continuous preview corners without rounding the paired seam")
    func matchingLoadingAndArtworkCorners() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 70, height: 100)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 70, height: 100))
        }
        for pages in [[1], [1, 2]] {
            let preview = SumiSpreadThumbnailView(frame: CGRect(x: 0, y: 0, width: CGFloat(pages.count) * 25.2, height: 36))
            preview.configure(identity: "loading", pages: pages, reversed: false, provider: { _ in nil })
            preview.layoutIfNeeded()
            let radius = preview.layer.cornerRadius
            #expect(radius == 8)
            #expect(preview.layer.cornerCurve == .continuous)
            let placeholders = preview.subviews.filter { $0.accessibilityIdentifier?.contains("PreviewPlaceholder") == true }
            #expect(placeholders.count == pages.count)
            for placeholder in placeholders {
                #expect(placeholder.layer.cornerRadius == radius)
                #expect(placeholder.layer.cornerCurve == .continuous && placeholder.clipsToBounds)
            }
            preview.configure(identity: "loaded", pages: pages, reversed: false, provider: { _ in image })
            for _ in 0..<100 where preview.displayedPages != pages { await Task.yield() }
            preview.layoutIfNeeded()
            let art = preview.subviews.compactMap { $0 as? UIImageView }.prefix(pages.count)
            #expect(art.count == pages.count)
            for (index, leaf) in art.enumerated() {
                #expect(leaf.layer.cornerRadius == radius)
                #expect(leaf.layer.cornerCurve == .continuous && leaf.clipsToBounds)
                #expect(leaf.layer.maskedCorners == placeholders[index].layer.maskedCorners)
                if pages.count > 1 {
                    #expect(!leaf.layer.maskedCorners.contains(index == 0 ? .layerMaxXMinYCorner : .layerMinXMinYCorner))
                }
            }
        }
    }

    @Test("Tall source artwork fills both compact and hovering preview leaves without a thin fit strip")
    func tallArtworkFillsPreviewSurface() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 3000)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 3000))
        }
        for leafSize in [CGSize(width: 25.2, height: 36), CGSize(width: 122, height: 174)] {
            for pages in [[1], [1, 2]] {
                let preview = SumiSpreadThumbnailView(frame: CGRect(origin: .zero,
                    size: CGSize(width: leafSize.width * CGFloat(pages.count), height: leafSize.height)))
                preview.configure(identity: "tall", pages: pages, reversed: false, provider: { _ in image })
                for _ in 0..<100 where preview.displayedPages != pages { await Task.yield() }
                preview.layoutIfNeeded()
                let leaves = preview.subviews.compactMap { $0 as? UIImageView }.prefix(pages.count)
                for (index, leaf) in leaves.enumerated() {
                    #expect(abs(leaf.frame.minX - CGFloat(index) * leafSize.width) < 0.001)
                    #expect(abs(leaf.frame.minY) < 0.001)
                    #expect(abs(leaf.frame.width - leafSize.width) < 0.001)
                    #expect(abs(leaf.frame.height - leafSize.height) < 0.001)
                    #expect(leaf.contentMode == .scaleAspectFill && leaf.clipsToBounds)
                }
            }
        }
    }

    @Test("A grouping change reanchors the same canonical page with the new compact pitch")
    func groupingChangesReanchorCanonicalPage() throws {
        let scrubber = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 300, height: 48))
        scrubber.update(chapterKey: "same", totalPages: 6, currentPage: 4)
        scrubber.layoutIfNeeded()
        let strip = try #require(descendants(scrubber, type: UICollectionView.self).first)
        let flow = try #require(strip.collectionViewLayout as? SumiFilmstripLayout)
        #expect(flow.pitch == 30)
        scrubber.scrollViewWillBeginDragging(strip)
        strip.contentOffset.x += 11.25
        let activeOffset = strip.contentOffset
        scrubber.update(chapterKey: "same", totalPages: 6, currentPage: 4)
        scrubber.layoutIfNeeded()
        #expect(strip.contentOffset == activeOffset)
        scrubber.update(chapterKey: "same", totalPages: 6, currentPage: 4,
            spreads: [[1, 2], [3, 4], [5, 6]])
        scrubber.layoutIfNeeded()
        #expect(flow.pitch == 55)
        try expectCentered(strip, physicalIndex: 1)
        #expect(scrubber.accessibilityValue == "Pages 3–4 of 6")
    }

    @Test("Replacing a model cancels the prior pan and reanchors its canonical page even at the same pitch")
    func samePitchModelChangeCancelsOldPan() throws {
        for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
            for reversed in [false, true] {
                let size = axis == .horizontal ? CGSize(width: 300, height: 48) : CGSize(width: 48, height: 300)
                let scrubber = SumiPageScrubber(frame: CGRect(origin: .zero, size: size))
                scrubber.axis = axis
                scrubber.isReversed = reversed
                var commits: [Int] = []
                scrubber.onCommit = { commits.append($0) }
                scrubber.update(chapterKey: "same", totalPages: 6, currentPage: 4,
                    spreads: [[1, 2], [3, 4], [5, 6]])
                scrubber.layoutIfNeeded()
                let strip = try #require(descendants(scrubber, type: UICollectionView.self).first)
                let flow = try #require(strip.collectionViewLayout as? SumiFilmstripLayout)
                let pitch = flow.pitch
                let regrouped = [[1], [2, 3], [4, 5], [6]]

                scrubber.scrollViewWillBeginDragging(strip)
                strip.contentOffset.x += pitch + 0.25
                scrubber.update(chapterKey: "same", totalPages: 6, currentPage: 4, spreads: regrouped)
                scrubber.layoutIfNeeded()
                #expect(flow.pitch == pitch)
                #expect(scrubber.accessibilityValue == "Pages 4–5 of 6")
                try expectCentered(strip, physicalIndex: reversed ? 1 : 2)
                scrubber.scrollViewDidEndDragging(strip, willDecelerate: false)
                scrubber.scrollViewDidEndDecelerating(strip)
                #expect(commits.isEmpty, "The canceled gesture must not commit its old preview")

                scrubber.scrollViewWillBeginDragging(strip)
                strip.contentOffset.x += pitch + 0.25
                scrubber.update(chapterKey: "next", totalPages: 6, currentPage: 2, spreads: regrouped)
                scrubber.layoutIfNeeded()
                #expect(flow.pitch == pitch)
                #expect(scrubber.accessibilityValue == "Pages 2–3 of 6")
                try expectCentered(strip, physicalIndex: reversed ? 2 : 1)
                scrubber.scrollViewDidEndDragging(strip, willDecelerate: false)
                #expect(commits.isEmpty)
            }
        }
    }
}
