@testable import Aidoku
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct ReaderPageGestureHandoffTests {
    @Test("Fit pages without sideways content yield horizontal pans, including fractional book halves")
    func fitBaselineHandoff() {
        let scroll = makePage()
        scroll.applyPageSizing(.fit, resetZoom: true)
        #expect(scroll.zoomScale == 1)
        #expect(!scroll.permitsPagePan(velocity: CGPoint(x: -300, y: 20)))
        #expect(!scroll.permitsPagePan(velocity: CGPoint(x: 300, y: -20)))
        #expect(scroll.permitsPagePan(velocity: CGPoint(x: 20, y: 300)))
        #expect(scroll.permitsPagePan(velocity: CGPoint(x: 300, y: 20), touchCount: 2))
        #expect(scroll.pinchGestureRecognizer?.isEnabled == true)
        // A one-pixel layout remainder is not useful sideways reading content.
        scroll.contentSize.width += 0.5 / max(1, scroll.traitCollection.displayScale)
        #expect(!scroll.permitsPagePan(velocity: CGPoint(x: 300, y: 20)))
    }

    @Test("Manual Fit zoom retains native panning at both image edges")
    func zoomedPageKeepsPanning() {
        let scroll = makePage()
        scroll.applyPageSizing(.fit, resetZoom: true)
        scroll.setZoomScale(2.4, animated: false)
        #expect(scroll.contentSize.width > scroll.bounds.width + 100)
        let left = -scroll.adjustedContentInset.left
        let right = scroll.contentSize.width - scroll.bounds.width + scroll.adjustedContentInset.right
        for x in [left, right] {
            scroll.setContentOffset(CGPoint(x: x, y: 100), animated: false)
            let offset = scroll.contentOffset
            #expect(scroll.permitsPagePan(velocity: CGPoint(x: -300, y: 20)))
            #expect(scroll.permitsPagePan(velocity: CGPoint(x: 300, y: -20)))
            #expect(scroll.contentOffset == offset)
            #expect(abs(scroll.zoomScale - 2.4) < 0.001)
        }
        #expect(scroll.bounces)
        #expect(scroll.pinchGestureRecognizer?.isEnabled == true)
    }

    @Test("Fill Width keeps independent vertical scrolling and bounce while yielding sideways pans")
    func fillKeepsVerticalMovement() {
        let scroll = makePage()
        scroll.applyPageSizing(.fill, resetZoom: true)
        let offset = scroll.contentOffset
        let insets = scroll.contentInset
        #expect(!scroll.permitsPagePan(velocity: CGPoint(x: 300, y: 20)))
        #expect(scroll.permitsPagePan(velocity: CGPoint(x: 20, y: -300)))
        #expect(scroll.permitsPagePan(velocity: CGPoint(x: -20, y: 300)))
        #expect(scroll.contentOffset == offset)
        #expect(scroll.contentInset == insets)
        #expect(scroll.bounces && scroll.alwaysBounceVertical)
        #expect(scroll.pinchGestureRecognizer?.isEnabled != true)
    }

    private func makePage() -> ZoomableScrollView {
        let scroll = ZoomableScrollView(frame: CGRect(x: 0, y: 0, width: 475.5, height: 669))
        let content = UIView(frame: scroll.bounds)
        scroll.addSubview(content)
        scroll.zoomView = content
        scroll.contentSize = content.bounds.size
        scroll.pageContentFrame = {
            ReaderPageSizingGeometry.aspectFitFrame(imageSize: CGSize(width: 200, height: 800), in: content.bounds)
        }
        return scroll
    }
}
