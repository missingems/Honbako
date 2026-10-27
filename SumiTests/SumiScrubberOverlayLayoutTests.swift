@testable import Sumi
import Testing
import UIKit

struct SumiScrubberOverlayLayoutTests {
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
        let glass = try #require(preview.subviews.first { $0 is SumiScrubHoverGlassView })
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
