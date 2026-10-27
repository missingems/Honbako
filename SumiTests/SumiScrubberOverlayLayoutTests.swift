@testable import Sumi
import Testing
import UIKit

struct SumiScrubberOverlayLayoutTests {
    @Test("A shrinking hover preserves its horizontal and vertical anchor centers before edge clamping")
    func shrinkingKeepsCenter() {
        let horizontal = SumiScrubberOverlayLayout.frame(CGRect(x: 240, y: 0, width: 280, height: 200),
            anchor: CGRect(x: 356, y: 300, width: 48, height: 40),
            in: CGRect(x: 0, y: 0, width: 900, height: 140), avoiding: [], preservesAspect: true)
        #expect(abs(horizontal.midX - 380) < 0.001)
        #expect(horizontal.height == 140)
        let vertical = SumiScrubberOverlayLayout.frame(CGRect(x: 20, y: 250, width: 240, height: 300),
            anchor: CGRect(x: 300, y: 376, width: 40, height: 48),
            in: CGRect(x: 20, y: 20, width: 80, height: 700), avoiding: [], preservesAspect: true)
        #expect(abs(vertical.midY - 400) < 0.001)
        #expect(vertical.width == 80)
    }

    @Test("Physical rail anchors put a bottom hover above its center and side hovers inward at the same height")
    func preferredAnchorCenters() {
        let anchor = CGRect(x: 300, y: 400, width: 40, height: 48)
        let size = CGSize(width: 210, height: 300)
        let bottom = SumiScrubberOverlayLayout.preferredFrame(size: size, anchor: anchor,
            axis: .horizontal, sidebarEdge: .right, gap: 12)
        #expect(bottom.midX == anchor.midX)
        #expect(bottom.maxY == anchor.minY - 12)
        let right = SumiScrubberOverlayLayout.preferredFrame(size: size, anchor: anchor,
            axis: .vertical, sidebarEdge: .right, gap: 12)
        #expect(right.midY == anchor.midY)
        #expect(right.maxX == anchor.minX - 12)
        let left = SumiScrubberOverlayLayout.preferredFrame(size: size, anchor: anchor,
            axis: .vertical, sidebarEdge: .left, gap: 12)
        #expect(left.midY == anchor.midY)
        #expect(left.minX == anchor.maxX + 12)
    }

    @MainActor
    @Test("A visible hover follows a relocated bottom strip and resized reader instead of retaining its first lift target")
    func visibleHoverRelayout() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let scrubber = SumiPageScrubber(frame: CGRect(x: 80, y: 680, width: 600, height: 40))
        host.addSubview(scrubber)
        scrubber.previewContainer = host
        scrubber.update(chapterKey: "relocation", totalPages: 2, currentPage: 1)
        scrubber.preview(at: CGPoint(x: 30, y: 20))
        scrubber.updateFloatingLayout()
        let preview = try liftedPreview(in: scrubber)
        #expect(abs(preview.convert(preview.bounds, to: host).midX - scrubber.frame.midX) < 0.001)

        scrubber.frame.origin.x = 320
        scrubber.updateFloatingLayout()
        #expect(!preview.isHidden)
        #expect(abs(preview.convert(preview.bounds, to: host).midX - scrubber.frame.midX) < 0.001)
        host.bounds.size = CGSize(width: 800, height: 1000)
        scrubber.frame = CGRect(x: 20, y: 930, width: 760, height: 40)
        scrubber.updateFloatingLayout()
        #expect(abs(preview.convert(preview.bounds, to: host).midX - 400) < 0.001)
        scrubber.cancelPreview()
    }

    @MainActor
    @Test("A toolbar in a sibling view aligns with its reader overlay even when the reader has a nonzero bounds origin")
    func commonSuperviewCoordinates() throws {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 1000, height: 900))
        let reader = UIView(frame: CGRect(x: 100, y: 60, width: 800, height: 760))
        reader.bounds.origin = CGPoint(x: 37, y: 29)
        root.addSubview(reader)
        let toolbar = UIView(frame: CGRect(x: 200, y: 680, width: 600, height: 48))
        root.addSubview(toolbar)
        let scrubber = SumiPageScrubber(frame: CGRect(x: 54, y: 4, width: 492, height: 40))
        toolbar.addSubview(scrubber)
        scrubber.previewContainer = reader
        scrubber.update(chapterKey: "sibling", totalPages: 2, currentPage: 1)
        scrubber.preview(at: CGPoint(x: 30, y: 20))
        scrubber.updateFloatingLayout()
        let preview = try liftedPreview(in: scrubber)
        let visibleFrame = preview.convert(preview.bounds, to: root)
        let stripFrame = scrubber.convert(scrubber.bounds, to: root)
        #expect(abs(visibleFrame.midX - stripFrame.midX) < 0.001)
        #expect(visibleFrame.maxY < stripFrame.minY)
        #expect(reader.convert(reader.bounds, to: root).contains(visibleFrame))
        scrubber.cancelPreview()
    }

    @MainActor
    @Test("Duo's left and right physical rail keep an upright hover centered on the rail")
    func verticalRailCenters() throws {
        for edge: UIRectEdge in [.left, .right] {
            let host = UIView(frame: CGRect(x: 0, y: 0, width: 900, height: 800))
            let scrubber = SumiPageScrubber(frame: CGRect(x: edge == .left ? 20 : 840, y: 180, width: 40, height: 380))
            host.addSubview(scrubber)
            scrubber.axis = .vertical
            scrubber.sidebarEdge = edge
            scrubber.previewContainer = host
            scrubber.update(chapterKey: "vertical", totalPages: 2, currentPage: 1)
            scrubber.preview(at: CGPoint(x: 20, y: 30))
            scrubber.updateFloatingLayout()
            let preview = try liftedPreview(in: scrubber)
            let frame = preview.convert(preview.bounds, to: host)
            #expect(abs(frame.midY - scrubber.frame.midY) < 0.001)
            if edge == .left { #expect(frame.minX > scrubber.frame.maxX) }
            else { #expect(frame.maxX < scrubber.frame.minX) }
            scrubber.cancelPreview()
        }
    }

    @MainActor
    private func liftedPreview(in scrubber: SumiPageScrubber) throws -> UIView {
        let overlay = try #require(scrubber.accessibilityOverlayView)
        return try #require(overlay.subviews.first { $0.accessibilityIdentifier == "Sumi.Reader.ScrubPreview" })
    }

    @MainActor
    @Test("The complete hovering glass stays inside a narrow reader after fitting a paired spread")
    func hoverGlassFitsSmallReader() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 240, height: 320))
        let scrubber = SumiPageScrubber(frame: CGRect(x: 10, y: 270, width: 220, height: 40))
        host.addSubview(scrubber)
        scrubber.previewContainer = host
        scrubber.update(chapterKey: "narrow", totalPages: 4, currentPage: 1, spreads: [[1, 2], [3, 4]])
        scrubber.layoutIfNeeded()
        scrubber.preview(at: CGPoint(x: 30, y: 20))
        scrubber.layoutIfNeeded()
        let overlay = try #require(scrubber.accessibilityOverlayView)
        let preview = try #require(overlay.subviews.first { $0.accessibilityIdentifier == "Sumi.Reader.ScrubPreview" })
        let glass = try #require(preview.subviews.flatMap { $0.subviews }.first { $0 is SumiScrubHoverGlassView })
        let frame = glass.convert(glass.bounds, to: host)
        #expect(host.bounds.insetBy(dx: 8, dy: 8).contains(frame))
        #expect(frame.maxY < scrubber.frame.minY, "The entire glass lip remains above the strip")
        #expect(!glass.isUserInteractionEnabled, "The floating effect cannot steal a drag from the filmstrip")
        scrubber.cancelPreview()
        #expect(preview.isHidden)
    }

    @Test("A preview stays in the same narrow pane as the right toolbar and avoids the fold")
    func foldedRightPane() {
        let bounds = CGRect(x: 8, y: 46, width: 630, height: 546)
        let fold = CGRect(x: 330, y: 0, width: 40, height: 600)
        let anchor = CGRect(x: 652, y: 268, width: 48, height: 64)
        let preferred = CGRect(x: 294, y: 210, width: 244, height: 174)
        let fitted = SumiScrubberOverlayLayout.frame(preferred, anchor: anchor, in: bounds,
            avoiding: [fold], preservesAspect: true)
        #expect(fitted.minX >= fold.maxX)
        #expect(fitted.maxX <= bounds.maxX)
        #expect(bounds.contains(fitted))
        #expect(!fitted.intersects(fold))
        #expect(abs(fitted.width / fitted.height - preferred.width / preferred.height) < 0.001)
    }

    @Test("A tiny reader pane scales the print instead of clipping or crossing the toolbar")
    func resizedWindow() {
        let bounds = CGRect(x: 8, y: 46, width: 142, height: 156)
        let fitted = SumiScrubberOverlayLayout.frame(CGRect(x: -62, y: -10, width: 244, height: 174),
            anchor: CGRect(x: 164, y: 90, width: 48, height: 64), in: bounds,
            avoiding: [], preservesAspect: true)
        #expect(bounds.contains(fitted))
        #expect(fitted.width < 244)
        #expect(abs(fitted.width / fitted.height - 244.0 / 174) < 0.001)
    }

    @Test("The page badge remains visible around a camera cutout without shrinking its text height")
    func cameraBadge() {
        let bounds = CGRect(x: 8, y: 8, width: 384, height: 584)
        let camera = CGRect(x: 140, y: 0, width: 120, height: 55)
        let preferred = CGRect(x: 150, y: 15, width: 140, height: 30)
        let fitted = SumiScrubberOverlayLayout.frame(preferred,
            anchor: CGRect(x: 160, y: 90, width: 64, height: 48), in: bounds,
            avoiding: [camera], preservesAspect: false)
        #expect(bounds.contains(fitted))
        #expect(!fitted.intersects(camera))
        #expect(fitted.height == 30)
    }
}
