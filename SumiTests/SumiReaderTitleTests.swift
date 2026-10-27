@testable import Sumi
import Testing
import UIKit

@MainActor
struct SumiReaderTitleTests {
    @Test("The book title appears with controls and remains a noninteractive accessible heading")
    func titlePresentation() {
        let title = SumiReaderTitleView(title: "One Punch Man")
        #expect(title.isHidden)
        #expect(!title.isUserInteractionEnabled)
        #expect(title.accessibilityLabel == "One Punch Man")
        #expect(title.accessibilityTraits.contains(.header))
        title.setVisible(true, animated: false)
        #expect(title.isVisible && !title.isHidden && title.alpha == 1)
        title.setVisible(false, animated: false)
        #expect(!title.isVisible && title.isHidden && title.alpha == 0)
    }

    @Test("The closed display title respects the physical status rail and camera")
    func closedDisplay() {
        let bounds = CGRect(x: 0, y: 0, width: 466, height: 678)
        let camera = CGRect(x: 402, y: 0, width: 64, height: 100)
        let frame = SumiReaderTitleLayout.frame(in: bounds,
            safeAreaInsets: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 84), avoiding: [camera],
            size: CGSize(width: 300, height: 36), side: nil)
        #expect(frame.maxX <= bounds.maxX - 84)
        #expect(frame.minY >= 8)
        #expect(!frame.intersects(camera))
    }

    @Test("Titles stay within one leaf when a fold divides the inner display")
    func foldedDisplay() {
        let bounds = CGRect(x: 0, y: 0, width: 951, height: 669)
        let fold = CGRect(x: 460, y: 0, width: 31, height: 669)
        for side in [UIRectEdge.left, .right] {
            let frame = SumiReaderTitleLayout.frame(in: bounds, safeAreaInsets: .zero, avoiding: [fold],
                size: CGSize(width: 480, height: 36), side: side)
            #expect(!frame.intersects(fold))
            #expect(bounds.contains(frame))
            if side == .left { #expect(frame.maxX <= fold.minX) }
            else { #expect(frame.minX >= fold.maxX) }
        }
    }

    @Test("Portrait titles remain centered below the actual top safe area")
    func portraitDisplay() {
        let bounds = CGRect(x: 0, y: 0, width: 402, height: 874)
        let frame = SumiReaderTitleLayout.frame(in: bounds,
            safeAreaInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0), avoiding: [],
            size: CGSize(width: 180, height: 36), side: nil)
        #expect(frame.midX == bounds.midX)
        #expect(frame.minY == 67)
        #expect(frame.width == 180 && frame.height == 36)
    }
}
