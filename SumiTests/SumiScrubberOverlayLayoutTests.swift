@testable import Sumi
import Testing
import UIKit

struct SumiScrubberOverlayLayoutTests {
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
