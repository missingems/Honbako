@testable import Sumi
import Testing
import UIKit

@MainActor
struct SumiScrubberAdaptiveTests {
    private func descendants<T: UIView>(_ view: UIView, type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type: type) }
    }

    @Test("The side toolbar keeps navigation targets separate from the vertical page strip")
    func integratedSidebarToolbar() throws {
        let reader = UIView(frame: CGRect(x: 0, y: 0, width: 466, height: 678))
        let toolbar = SumiReaderToolbar(frame: CGRect(x: 410, y: 149, width: 48, height: 380))
        reader.addSubview(toolbar)
        let scrubber = SumiPageScrubber()
        scrubber.previewContainer = reader
        toolbar.axis = .vertical
        toolbar.sidebarEdge = .right
        toolbar.mount(scrubber)
        scrubber.update(chapterKey: "one", totalPages: 6, currentPage: 3)
        toolbar.layoutIfNeeded()
        let buttons = descendants(toolbar, type: UIButton.self)
        let close = try #require(buttons.first { $0.accessibilityIdentifier == "SumiReader.Close" })
        let chapters = try #require(buttons.first { $0.accessibilityIdentifier == "Sumi.Reader.ChaptersButton" })
        let closeFrame = close.convert(close.bounds, to: toolbar)
        let chaptersFrame = chapters.convert(chapters.bounds, to: toolbar)
        let stripFrame = scrubber.convert(scrubber.bounds, to: toolbar)
        #expect(scrubber.axis == .vertical)
        #expect(stripFrame.height > stripFrame.width)
        #expect(closeFrame.width >= 44 && closeFrame.height >= 44)
        #expect(chaptersFrame.width >= 44 && chaptersFrame.height >= 44)
        #expect(closeFrame.maxY < stripFrame.minY)
        #expect(chaptersFrame.minY > stripFrame.maxY)
        let badge = try #require(scrubber.accessibilityOverlayView?.subviews.first {
            $0.accessibilityIdentifier == "Sumi.Reader.PagePosition"
        })
        #expect(badge.frame.maxX < toolbar.frame.minX)
    }

    @Test("Compact spread previews fit both toolbar axes without magnifying the selected spread")
    func enlargedPrintedPreviews() throws {
        for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
            let reader = UIView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
            let toolbar = SumiReaderToolbar()
            toolbar.axis = axis
            toolbar.frame = CGRect(origin: .zero, size: toolbar.preferredSize(availableLength: 420))
            reader.addSubview(toolbar)
            let scrubber = SumiPageScrubber()
            toolbar.mount(scrubber)
            scrubber.update(chapterKey: "readable", totalPages: 6, currentPage: 3,
                spreads: [[1, 2], [3, 4], [5, 6]])
            toolbar.layoutIfNeeded()
            let strip = try #require(descendants(scrubber, type: UICollectionView.self).first)
            strip.layoutIfNeeded()
            let cells = strip.visibleCells.compactMap { $0 as? SumiPageThumbnailCell }
            #expect(cells.count >= 3)
            var sizes: [CGSize] = []
            for cell in cells {
                cell.layoutIfNeeded()
                let print = try #require(descendants(cell, type: SumiSpreadThumbnailView.self).first)
                #expect(print.bounds.height >= 28 && print.bounds.height <= 36)
                #expect(print.bounds.width / 2 >= 20)
                #expect(abs(print.bounds.width / print.bounds.height - 1.4) < 0.001)
                sizes.append(print.bounds.size)
            }
            let printedSize = try #require(sizes.first)
            #expect(sizes.dropFirst().allSatisfy { $0 == printedSize },
                "The selected spread uses the same printed size as its neighbors")
            #expect(axis == .vertical ? toolbar.bounds.width == 48 : toolbar.bounds.height == 48)
        }
    }

    @Test("The same native strip stands vertically in a 48-point sidebar and selects canonical pages")
    func verticalRail() throws {
        let scrubber = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 48, height: 260))
        scrubber.axis = .vertical
        scrubber.update(chapterKey: "one", totalPages: 6, currentPage: 3, spreads: [[1, 2], [3, 4], [5, 6]])
        scrubber.layoutIfNeeded()
        let strip = try #require(descendants(scrubber, type: UICollectionView.self).first)
        let visibleFrame = strip.convert(strip.bounds, to: scrubber)
        #expect(abs(visibleFrame.width - 48) < 0.01)
        #expect(abs(visibleFrame.height - 244) < 0.01)
        #expect(abs(visibleFrame.midX - 24) < 0.01)
        #expect(abs(visibleFrame.midY - 130) < 0.01)
        var committed: [Int] = []
        scrubber.onCommit = { committed.append($0) }
        scrubber.preview(at: CGPoint(x: 24, y: 245))
        scrubber.finishPreview(commit: true)
        #expect(committed == [5])
        scrubber.preview(at: CGPoint(x: 24, y: 15))
        scrubber.finishPreview(commit: true)
        #expect(committed == [5, 1])
    }

    @Test("A side preview opens inward, and page artwork remains upright")
    func inwardSidebarPreview() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 70, height: 100)).image { _ in }
        let scrubber = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 48, height: 260))
        scrubber.axis = .vertical
        scrubber.imageProvider = { _ in image }
        scrubber.update(chapterKey: "one", totalPages: 4, currentPage: 1, spreads: [[1, 2], [3, 4]])
        scrubber.layoutIfNeeded()
        let preview = try #require(scrubber.subviews.first { $0.accessibilityIdentifier == "Sumi.Reader.ScrubPreview" })
        scrubber.sidebarEdge = .right
        scrubber.preview(at: CGPoint(x: 24, y: 245))
        scrubber.layoutIfNeeded()
        for _ in 0..<80 { await Task.yield() }
        #expect(preview.bounds.width > 100)
        // Target pose is inward; the lift may still be animating to it.
        #expect(preview.layer.transform.m12 == 0 && preview.layer.transform.m21 == 0)
        scrubber.cancelPreview()
        scrubber.sidebarEdge = .left
        scrubber.layoutIfNeeded()
        let badge = try #require(descendants(scrubber, type: UIVisualEffectView.self).first { $0.accessibilityIdentifier == "Sumi.Reader.PagePosition" })
        #expect(badge.frame.minX > scrubber.bounds.maxX)
    }

    @Test("The toolbar's floating preview and label are hosted by the reader overlay")
    func previewEscapesToolbarClipping() throws {
        let reader = UIView(frame: CGRect(x: 0, y: 0, width: 700, height: 600))
        let toolbar = UIView(frame: CGRect(x: 652, y: 160, width: 48, height: 260))
        toolbar.clipsToBounds = true
        reader.addSubview(toolbar)
        let scrubber = SumiPageScrubber(frame: toolbar.bounds)
        toolbar.addSubview(scrubber)
        scrubber.axis = .vertical
        scrubber.previewContainer = reader
        scrubber.update(chapterKey: "one", totalPages: 6, currentPage: 3)
        scrubber.layoutIfNeeded()
        let overlay = try #require(scrubber.accessibilityOverlayView)
        #expect(overlay.superview === reader)
        let badge = try #require(overlay.subviews.first { $0.accessibilityIdentifier == "Sumi.Reader.PagePosition" })
        let preview = try #require(overlay.subviews.first { $0.accessibilityIdentifier == "Sumi.Reader.ScrubPreview" })
        #expect(badge.superview !== toolbar)
        #expect(preview.superview !== toolbar)
        #expect(badge.frame.maxX < toolbar.frame.minX)
        scrubber.alpha = 0.4
        #expect(abs(overlay.alpha - 0.4) < 0.000001)
        scrubber.isHidden = true
        #expect(overlay.isHidden)
    }

    @Test("Animated navigation stays visible and reports actual cancellation instead of mounting a raster")
    func animatedCommitHasNoOpaqueHandoff() async throws {
        let host = UIViewController()
        host.loadViewIfNeeded()
        let surface = UIView(frame: CGRect(x: 0, y: 0, width: 500, height: 500))
        host.view.addSubview(surface)
        let scrubber = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 360, height: 48))
        host.view.addSubview(scrubber)
        scrubber.landingSurface = { surface }
        scrubber.preparePage = { _ in true }
        var pending: CheckedContinuation<Bool, Never>?
        var requested: [Int] = [], legacy: [Int] = []
        scrubber.navigateToPage = { page in
            requested.append(page)
            return await withCheckedContinuation { pending = $0 }
        }
        scrubber.onCommit = { legacy.append($0) }
        scrubber.update(chapterKey: "one", totalPages: 6, currentPage: 1)
        scrubber.preview(at: CGPoint(x: 345, y: 20))
        scrubber.finishPreview(commit: true)
        for _ in 0..<100 where pending == nil { await Task.yield() }
        #expect(requested == [6])
        #expect(legacy.isEmpty)
        #expect(!host.view.subviews.contains { $0.accessibilityIdentifier == "Sumi.Reader.ScrubHandoff" })
        // The real reader may complete some adjacent curls before cancellation.
        scrubber.update(chapterKey: "one", totalPages: 6, currentPage: 3)
        pending?.resume(returning: false)
        for _ in 0..<100 { await Task.yield() }
        #expect(scrubber.accessibilityValue == "Page 3 of 6")
        #expect(legacy.isEmpty)
    }
}
