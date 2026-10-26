@testable import Sumi
import Testing
import UIKit

@MainActor
struct SumiPageScrubberTests {
    private func thumbnailStrip(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        return view.subviews.lazy.compactMap { self.thumbnailStrip(in: $0) }.first
    }

    @Test("A leftward native drag reveals later manga spreads for either source leaf order")
    func mangaStripDirectionIsIndependentOfSourceOrder() throws {
        for reversedPages in [false, true] {
            let scrubber = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 360, height: 90))
            scrubber.isReversed = false
            scrubber.reversesThumbnailPages = reversedPages
            scrubber.update(chapterKey: "one", totalPages: 6, currentPage: 3, spreads: [[1, 2], [3, 4], [5, 6]])
            scrubber.layoutIfNeeded()
            let strip = try #require(thumbnailStrip(in: scrubber))
            let flow = try #require(strip.collectionViewLayout as? SumiFilmstripLayout)
            strip.layoutIfNeeded()
            let left = IndexPath(item: 0, section: 0), right = IndexPath(item: 2, section: 0)
            let leftCell = try #require(strip.cellForItem(at: left) as? SumiPageThumbnailCell)
            let rightCell = try #require(strip.cellForItem(at: right) as? SumiPageThumbnailCell)
            #expect(leftCell.group == 0)
            #expect(rightCell.group == 2)
            let leftPosition = try #require(strip.collectionViewLayout.layoutAttributesForItem(at: left))
            let rightPosition = try #require(strip.collectionViewLayout.layoutAttributesForItem(at: right))
            #expect(leftPosition.center.x < rightPosition.center.x)

            // A leftward finger drag increases native contentOffset and
            // reveals later spreads without committing mid-drag.
            var commits: [Int] = []
            scrubber.onCommit = { commits.append($0) }
            scrubber.scrollViewWillBeginDragging(strip)
            strip.contentOffset.x += flow.pitch
            scrubber.scrollViewDidScroll(strip)
            #expect(scrubber.accessibilityValue == "Pages 5–6 of 6")
            #expect(commits.isEmpty)
            scrubber.cancelPreview()
            scrubber.scrollViewDidEndDragging(strip, willDecelerate: true)
            #expect(scrubber.accessibilityValue == "Pages 3–4 of 6")

            // Coordinate-based selection and VoiceOver keep canonical meaning
            // independently of the source's physical page order.
            scrubber.preview(at: CGPoint(x: 345, y: 30))
            scrubber.finishPreview(commit: true)
            #expect(commits == [5])
            scrubber.accessibilityDecrement()
            #expect(commits == [5, 3])
            scrubber.accessibilityIncrement()
            #expect(commits == [5, 3, 5])
            scrubber.preview(at: CGPoint(x: 15, y: 30))
            scrubber.finishPreview(commit: true)
            #expect(commits == [5, 3, 5, 1])
        }
    }

    @Test("Thumbnail leaf placement follows its source without reversing manga progression")
    func sourceLeafPlacementDoesNotReverseStrip() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 70, height: 100)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 70, height: 100))
        }
        let scrubber = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 360, height: 90))
        scrubber.isReversed = false
        scrubber.imageProvider = { _ in image }
        scrubber.update(chapterKey: "one", totalPages: 6, currentPage: 3, spreads: [[1, 2], [3, 4], [5, 6]])
        for reversedPages in [false, true] {
            scrubber.reversesThumbnailPages = reversedPages
            scrubber.preview(at: CGPoint(x: 345, y: 30))
            let preview = try #require(scrubber.subviews.first { $0.accessibilityIdentifier == "Sumi.Reader.ScrubPreview" } as? SumiSpreadThumbnailView)
            let expected = reversedPages ? [6, 5] : [5, 6]
            for _ in 0..<100 where preview.displayedPages != expected { await Task.yield() }
            #expect(preview.displayedPages == expected)
            #expect(scrubber.accessibilityValue == "Pages 5–6 of 6")
            scrubber.cancelPreview()
        }
    }

    @Test("Touching and releasing the strip cannot move its neighboring previews")
    func continuousTouchGeometry() throws {
        let scrubber = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 360, height: 90))
        scrubber.update(chapterKey: "one", totalPages: 8, currentPage: 4)
        scrubber.layoutIfNeeded()
        let strip = try #require(thumbnailStrip(in: scrubber))
        let path = IndexPath(item: 4, section: 0)
        let resting = try #require(strip.collectionViewLayout.layoutAttributesForItem(at: path)?.copy() as? UICollectionViewLayoutAttributes)
        scrubber.scrollViewWillBeginDragging(strip)
        scrubber.layoutIfNeeded()
        let touching = try #require(strip.collectionViewLayout.layoutAttributesForItem(at: path))
        #expect(touching.center == resting.center)
        #expect(CATransform3DEqualToTransform(touching.transform3D, resting.transform3D))
        scrubber.finishPreview(commit: false)
        scrubber.layoutIfNeeded()
        let released = try #require(strip.collectionViewLayout.layoutAttributesForItem(at: path))
        #expect(released.center == resting.center)
        #expect(CATransform3DEqualToTransform(released.transform3D, resting.transform3D))
        scrubber.scrollViewDidEndDragging(strip, willDecelerate: false)
    }

    @Test("The centered page keeps the same print scale as its neighbors without a selection ring")
    func selectionDoesNotMagnifyThePrint() throws {
        let scrubber = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 360, height: 90))
        scrubber.update(chapterKey: "one", totalPages: 8, currentPage: 4)
        scrubber.layoutIfNeeded()
        let strip = try #require(thumbnailStrip(in: scrubber))
        for index in [2, 3, 4] {
            let item = try #require(strip.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0)))
            #expect(item.transform3D.m11 == 1)
            #expect(item.transform3D.m22 == 1)
        }
        let anchor = try #require(scrubber.subviews.flatMap(\.subviews)
            .first { $0.accessibilityIdentifier == "Sumi.Reader.SelectedSpread" })
        #expect(anchor.layer.sublayers?.isEmpty != false)
        #expect(anchor.layer.borderWidth == 0)
        #expect(anchor.accessibilityLabel == "Page 4")
    }

    @Test("An active pan and its native coast retain the exact scroll position")
    func nativePanAndCoastOwnOffset() throws {
        let scrubber = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 360, height: 90))
        scrubber.update(chapterKey: "one", totalPages: 8, currentPage: 4)
        scrubber.layoutIfNeeded()
        let strip = try #require(thumbnailStrip(in: scrubber))
        scrubber.scrollViewWillBeginDragging(strip)
        strip.contentOffset.x += 17
        let draggingOffset = strip.contentOffset
        scrubber.setNeedsLayout(); scrubber.layoutIfNeeded()
        scrubber.update(chapterKey: "one", totalPages: 8, currentPage: 4)
        scrubber.layoutIfNeeded()
        #expect(strip.contentOffset == draggingOffset, "Reader updates must not fight the active native pan")
        scrubber.scrollViewDidEndDragging(strip, willDecelerate: true)
        #expect(strip.contentOffset == draggingOffset, "Even a slow native coast must not be replaced by an instant snap")
        scrubber.cancelPreview()
    }

    @Test("Preparing a destination cannot round or recenter the strip's native landing")
    func preparationKeepsNativeLanding() async throws {
        let scrubber = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 360, height: 90))
        var pending: CheckedContinuation<Bool, Never>?
        scrubber.preparePage = { _ in await withCheckedContinuation { pending = $0 } }
        scrubber.update(chapterKey: "one", totalPages: 8, currentPage: 4)
        scrubber.layoutIfNeeded()
        let strip = try #require(thumbnailStrip(in: scrubber))
        let flow = try #require(strip.collectionViewLayout as? SumiFilmstripLayout)
        scrubber.scrollViewWillBeginDragging(strip)
        strip.contentOffset.x += flow.pitch + 0.25
        scrubber.scrollViewDidScroll(strip)
        let landedOffset = strip.contentOffset
        scrubber.scrollViewDidEndDragging(strip, willDecelerate: true)
        scrubber.scrollViewDidEndDecelerating(strip)
        for _ in 0..<100 where pending == nil { try await Task.sleep(for: .milliseconds(5)) }
        #expect(pending != nil)
        scrubber.layoutIfNeeded()
        #expect(strip.contentOffset == landedOffset)
        scrubber.update(chapterKey: "one", totalPages: 8, currentPage: 4)
        scrubber.layoutIfNeeded()
        #expect(strip.contentOffset == landedOffset, "The old reader's bookmark must not recenter a pending destination")
        pending?.resume(returning: false)
        for _ in 0..<10 { await Task.yield() }
        scrubber.cancelPreview()
    }

    @Test("A lone final page keeps the same hover height and center as a paired spread")
    func stableHoverGeometry() async throws {
        let scrubber = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 360, height: 90))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 70, height: 100)).image { _ in }
        scrubber.imageProvider = { _ in image }
        scrubber.update(chapterKey: "one", totalPages: 3, currentPage: 1, spreads: [[1, 2], [3]])
        scrubber.layoutIfNeeded()
        scrubber.preview(at: CGPoint(x: 15, y: 30))
        let preview = try #require(scrubber.subviews.first { $0.accessibilityIdentifier == "Sumi.Reader.ScrubPreview" } as? SumiSpreadThumbnailView)
        for _ in 0..<100 where preview.displayedPages != [1, 2] { await Task.yield() }
        scrubber.layoutIfNeeded()
        let height = preview.bounds.height, center = preview.center
        scrubber.preview(at: CGPoint(x: 345, y: 30))
        for _ in 0..<100 where preview.displayedPages != [3] { await Task.yield() }
        scrubber.layoutIfNeeded()
        #expect(preview.displayedPages == [3])
        #expect(preview.bounds.height == height)
        #expect(preview.center == center)
        scrubber.cancelPreview()
    }

    @Test("The handoff freezes both old leaves until the full destination has crossed display frames")
    func immutableRasterHandoff() async throws {
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 340))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let surface = UIView(frame: CGRect(x: 0, y: 0, width: 500, height: 300))
        let left = UIView(frame: CGRect(x: 0, y: 0, width: 250, height: 300))
        let right = UIView(frame: CGRect(x: 250, y: 0, width: 250, height: 300))
        left.backgroundColor = .red; right.backgroundColor = .blue
        surface.addSubview(left); surface.addSubview(right); host.view.addSubview(surface)
        let scrubber = SumiPageScrubber(frame: CGRect(x: 100, y: 292, width: 300, height: 48))
        host.view.addSubview(scrubber)
        let format = UIGraphicsImageRendererFormat()
        format.scale = surface.traitCollection.displayScale; format.opaque = true
        let original = UIGraphicsImageRenderer(bounds: surface.bounds, format: format).image { context in
            surface.layer.render(in: context.cgContext)
        }.pngData()
        var ready = false
        scrubber.landingSurface = { surface }
        scrubber.isLandingReady = { _ in ready }
        scrubber.preparePage = { _ in true }
        scrubber.onCommit = { _ in left.backgroundColor = .green }
        scrubber.update(chapterKey: "one", totalPages: 4, currentPage: 1, spreads: [[1, 2], [3, 4]])
        scrubber.preview(at: CGPoint(x: 290, y: 20)); scrubber.finishPreview(commit: true)
        for _ in 0..<100 where !host.view.subviews.contains(where: { $0.accessibilityIdentifier == "Sumi.Reader.ScrubHandoff" }) {
            await Task.yield()
        }
        let snapshot = try #require(host.view.subviews.first { $0.accessibilityIdentifier == "Sumi.Reader.ScrubHandoff" } as? UIImageView)
        #expect(snapshot.image?.pngData() == original)
        #expect(snapshot.alpha == 1)
        try await Task.sleep(for: .milliseconds(80))
        #expect(snapshot.superview != nil, "One ready leaf cannot uncover a mixed old/new spread")
        #expect(snapshot.image?.pngData() == original, "The handoff image must not change with underlying UIKit views")
        right.backgroundColor = .yellow; ready = true
        for _ in 0..<100 where snapshot.superview != nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(snapshot.superview == nil)
    }

    @Test("Same-chapter regrouping preserves a pending canonical destination until handoff completes")
    func pendingDestinationSurvivesRegrouping() async throws {
        let scrubber = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 360, height: 90))
        var committed: [Int] = []
        var pending: CheckedContinuation<Bool, Never>?
        scrubber.onCommit = { committed.append($0) }
        scrubber.preparePage = { _ in await withCheckedContinuation { pending = $0 } }
        scrubber.update(chapterKey: "one", totalPages: 4, currentPage: 2, spreads: [[1, 2], [3, 4]])
        scrubber.preview(at: CGPoint(x: 345, y: 30)); scrubber.finishPreview(commit: true)
        for _ in 0..<100 where pending == nil { await Task.yield() }
        scrubber.update(chapterKey: "one", totalPages: 4, currentPage: 2, spreads: [[1], [2, 3], [4]])
        #expect(scrubber.accessibilityValue == "Pages 3–4 of 4")
        #expect(committed.isEmpty)
        pending?.resume(returning: true)
        for _ in 0..<100 where committed.isEmpty { await Task.yield() }
        #expect(committed == [3], "A group-plan change must not cancel or redirect the pending source page")
        try await Task.sleep(for: .milliseconds(300))
        #expect(scrubber.accessibilityValue == "Pages 2–3 of 4")
        #expect(committed == [3])
    }

    @Test("Only the newest prepared destination commits, and a failed preparation keeps the bookmark")
    func destinationPreparation() async {
        let scrubber = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 360, height: 90))
        var committed: [Int] = []
        var pending: [Int: CheckedContinuation<Bool, Never>] = [:]
        scrubber.onCommit = { committed.append($0) }
        scrubber.preparePage = { page in await withCheckedContinuation { pending[page] = $0 } }
        scrubber.update(chapterKey: "one", totalPages: 8, currentPage: 4)
        scrubber.preview(at: CGPoint(x: 345, y: 30)); scrubber.finishPreview(commit: true)
        for _ in 0..<100 where pending[8] == nil { await Task.yield() }
        #expect(committed.isEmpty, "Loading a destination must not move the reader or save progress")
        scrubber.preview(at: CGPoint(x: 15, y: 30)); scrubber.finishPreview(commit: true)
        for _ in 0..<100 where pending[1] == nil { await Task.yield() }
        pending[1]?.resume(returning: true)
        for _ in 0..<100 where committed.isEmpty { await Task.yield() }
        #expect(committed == [1])
        pending[8]?.resume(returning: true)
        for _ in 0..<10 { await Task.yield() }
        #expect(committed == [1], "The older request must never commit after the newer one")
        scrubber.preview(at: CGPoint(x: 345, y: 30)); scrubber.finishPreview(commit: true)
        pending[8] = nil
        for _ in 0..<100 where pending[8] == nil { await Task.yield() }
        pending[8]?.resume(returning: false)
        for _ in 0..<100 where scrubber.accessibilityValue != "Page 1 of 8" { await Task.yield() }
        #expect(committed == [1])
        #expect(scrubber.accessibilityValue == "Page 1 of 8")
    }

    @Test("Scrubbing previews without changing the bookmark, commits once on release, and cancels cleanly")
    func transientPreviewAndCommit() {
        let scrubber = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 360, height: 90))
        var committed: [Int] = []
        scrubber.onCommit = { committed.append($0) }
        scrubber.update(chapterKey: "one", totalPages: 8, currentPage: 4)
        scrubber.layoutIfNeeded()
        scrubber.preview(at: CGPoint(x: 345, y: 30))
        #expect(scrubber.accessibilityValue == "Page 8 of 8")
        #expect(committed.isEmpty)
        scrubber.finishPreview(commit: false)
        #expect(scrubber.accessibilityValue == "Page 4 of 8")
        #expect(committed.isEmpty)
        scrubber.preview(at: CGPoint(x: 15, y: 30))
        #expect(scrubber.accessibilityValue == "Page 1 of 8")
        #expect(committed.isEmpty)
        scrubber.finishPreview(commit: true)
        #expect(committed == [1])
        #expect(scrubber.accessibilityValue == "Page 1 of 8")
        scrubber.finishPreview(commit: true)
        #expect(committed == [1], "A duplicate touch-end must not advance history twice")
        scrubber.isReversed = true
        scrubber.preview(at: CGPoint(x: 15, y: 30))
        #expect(scrubber.accessibilityValue == "Page 8 of 8")
        #expect(committed == [1])
        scrubber.finishPreview(commit: false)
        #expect(scrubber.accessibilityValue == "Page 1 of 8")
        #expect(committed == [1])
    }

    @Test("VoiceOver page adjustments commit real pages and respect chapter bounds")
    func accessiblePageNavigation() {
        let scrubber = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 360, height: 90))
        var committed: [Int] = []
        scrubber.onCommit = { committed.append($0) }
        scrubber.update(chapterKey: "one", totalPages: 8, currentPage: 4)
        #expect(scrubber.accessibilityValue == "Page 4 of 8")
        scrubber.accessibilityIncrement()
        #expect(committed == [5])
        #expect(scrubber.accessibilityValue == "Page 5 of 8")
        scrubber.accessibilityDecrement()
        #expect(committed == [5, 4])
        #expect(scrubber.accessibilityValue == "Page 4 of 8")
        // Reading direction reverses the visual strip, not the spoken meaning
        // of incrementing or decrementing a real chapter page.
        scrubber.isReversed = true
        scrubber.accessibilityIncrement()
        #expect(committed.last == 5)
        scrubber.update(chapterKey: "two", totalPages: 2, currentPage: 2)
        scrubber.accessibilityIncrement()
        #expect(committed.last == 2)
        #expect(scrubber.accessibilityValue == "Page 2 of 2")
        scrubber.update(chapterKey: "two", totalPages: 2, currentPage: 1)
        scrubber.accessibilityDecrement()
        #expect(committed.last == 1)
        #expect(scrubber.accessibilityValue == "Page 1 of 2")
    }

    @Test("Loading a chapter or cancelling a preview never invents a committed page")
    func chapterLoadingDoesNotCommit() {
        let scrubber = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 360, height: 90))
        var committed: [Int] = []
        scrubber.onCommit = { committed.append($0) }
        scrubber.update(chapterKey: "loading", totalPages: 0, currentPage: 0)
        scrubber.accessibilityIncrement()
        scrubber.accessibilityDecrement()
        #expect(!scrubber.isEnabled)
        #expect(committed.isEmpty)
        scrubber.update(chapterKey: "ready", totalPages: 8, currentPage: 6)
        scrubber.cancelPreview()
        #expect(committed.isEmpty)
        #expect(scrubber.accessibilityValue == "Page 6 of 8")
        scrubber.update(chapterKey: "another", totalPages: 3, currentPage: 1)
        #expect(committed.isEmpty)
        #expect(scrubber.accessibilityValue == "Page 1 of 3")
    }
}
