@testable import Sumi
import Testing
import UIKit

struct SumiReaderControlsLayoutTests {
    @Test("The open landscape book ignores only the unused side-bar insets")
    func openLandscapeSideInsets() {
        let original = UIEdgeInsets(top: 24, left: 0, bottom: 21, right: 84)
        let open = SumiReaderControlsLayout.toolbarInsets(original,
            systemUsesSideBars: false, ignoresSideInsets: true)
        #expect(open.left == 0 && open.right == 0)
        #expect(open.top == original.top && open.bottom == original.bottom)
        #expect(SumiReaderControlsLayout.toolbarInsets(original, systemUsesSideBars: false) == original)
        let bounds = CGRect(x: 0, y: 0, width: 951, height: 669)
        let frame = SumiReaderControlsLayout.toolbarFrame(in: bounds, safeAreaInsets: open,
            avoiding: [], side: .right, size: CGSize(width: 420, height: 48))
        #expect(frame.maxX > bounds.maxX - original.right)
        #expect(frame.minX > bounds.midX)
    }

    @Test("The open inner canvas uses bottom corners while the closed screen keeps its physical sidebar")
    func innerCanvasOverridesSystemSidebar() {
        for side in [UIRectEdge.left, .right] {
            #expect(SumiReaderControlsLayout.sidebarEdge(systemEdge: side, hasInnerFold: false) == side)
            #expect(SumiReaderControlsLayout.sidebarEdge(systemEdge: side, hasInnerFold: true) == nil)
        }
        #expect(SumiReaderControlsLayout.sidebarEdge(systemEdge: nil, hasInnerFold: false) == nil)
    }

    @Test("An open portrait inner canvas can anchor the larger strip to either touched bottom corner")
    func innerPortraitBottomCorners() {
        let bounds = CGRect(x: 0, y: 0, width: 669, height: 951)
        for side in [UIRectEdge.left, .right] {
            let frame = SumiReaderControlsLayout.toolbarFrame(in: bounds, safeAreaInsets: .zero,
                avoiding: [], side: side, size: CGSize(width: 420, height: 80))
            #expect(frame.height == 80)
            #expect(frame.maxY == bounds.maxY - 8)
            if side == .left { #expect(frame.maxX <= bounds.midX - 8) }
            else { #expect(frame.minX >= bounds.midX + 8) }
        }
    }

    @Test("A system sidebar occupies the reserved rail without applying the bar inset twice")
    func closedDuoSidebar() {
        let bounds = CGRect(x: 0, y: 0, width: 466, height: 678)
        let camera = CGRect(x: 402, y: 0, width: 64, height: 100)
        let insets = SumiReaderControlsLayout.toolbarInsets(UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 84),
            systemUsesSideBars: true)
        let frame = SumiReaderControlsLayout.toolbarFrame(in: bounds, safeAreaInsets: insets,
            avoiding: [camera], side: .right, size: CGSize(width: 56, height: 380), axis: .vertical)
        #expect(frame.width == 56 && frame.height == 380)
        #expect(frame.maxX == bounds.maxX - 8)
        #expect(frame.midY == bounds.midY)
        #expect(!frame.intersects(camera))
    }

    @Test("A side toolbar stays on the system edge and compresses below a corner camera")
    func compactSidebarCameraClearance() {
        let bounds = CGRect(x: 0, y: 0, width: 678, height: 466)
        for side in [UIRectEdge.left, .right] {
            let camera = CGRect(x: side == .left ? 0 : 578, y: 0, width: 100, height: 190)
            let frame = SumiReaderControlsLayout.toolbarFrame(in: bounds, safeAreaInsets: .zero,
                avoiding: [camera], side: side, size: CGSize(width: 56, height: 380), axis: .vertical)
            #expect(frame.width == 56 && frame.height >= 156 && frame.height < 380)
            #expect(!frame.intersects(camera))
            #expect(bounds.insetBy(dx: 8, dy: 8).contains(frame))
            if side == .left { #expect(frame.minX == 8) }
            else { #expect(frame.maxX == bounds.maxX - 8) }
        }
    }

    @Test("A side toolbar remains in its physical pane beside an active fold")
    func sidebarFoldClearance() {
        let bounds = CGRect(x: 0, y: 0, width: 951, height: 669)
        let fold = CGRect(x: 460, y: 0, width: 31, height: 669)
        for side in [UIRectEdge.left, .right] {
            let frame = SumiReaderControlsLayout.toolbarFrame(in: bounds, safeAreaInsets: .zero,
                avoiding: [fold], side: side, size: CGSize(width: 56, height: 380), axis: .vertical)
            #expect(!frame.intersects(fold))
            #expect(frame.width == 56 && frame.height == 380)
            if side == .left { #expect(frame.maxX < fold.minX) }
            else { #expect(frame.minX > fold.maxX) }
        }
    }

    @Test("Portrait controls stay centered above the home indicator despite asymmetric camera margins")
    func portraitBottomControls() {
        for bounds in [CGRect(x: 0, y: 0, width: 402, height: 874),
                       CGRect(x: 0, y: 0, width: 744, height: 1133)] {
            let insets = UIEdgeInsets(top: 24, left: 12, bottom: 34, right: 20)
            let frame = SumiReaderControlsLayout.toolbarFrame(in: bounds, safeAreaInsets: insets,
                avoiding: [], side: nil, size: CGSize(width: 330, height: 56))
            #expect(frame.midX == bounds.midX)
            #expect(frame.maxY == bounds.maxY - 38)
            #expect(frame.width > frame.height)
        }
    }

    @Test("Landscape taps place a horizontal strip at the bottom of the corresponding page")
    func bottomOfTappedLeaf() {
        for bounds in [CGRect(x: 0, y: 0, width: 1133, height: 744),
                       CGRect(x: 0, y: 0, width: 951, height: 669),
                       CGRect(x: 0, y: 0, width: 852, height: 393)] {
            for side in [UIRectEdge.left, .right] {
                let frame = SumiReaderControlsLayout.toolbarFrame(in: bounds,
                    safeAreaInsets: UIEdgeInsets(top: 24, left: 0, bottom: 21, right: 0),
                    avoiding: [], side: side, size: CGSize(width: 420, height: 56))
                #expect(frame.height == 56)
                #expect(frame.width > frame.height)
                #expect(frame.maxY == bounds.maxY - 25)
                if side == .left { #expect(frame.maxX <= bounds.midX - 8) }
                else { #expect(frame.minX >= bounds.midX + 8) }
            }
        }
    }

    @Test("Bottom controls avoid both a folded binding and a camera without changing their axis")
    func hardwareClearance() {
        let bounds = CGRect(x: 0, y: 0, width: 951, height: 669)
        let fold = CGRect(x: 460, y: 0, width: 31, height: 669)
        let camera = CGRect(x: 830, y: 580, width: 121, height: 89)
        for side in [UIRectEdge.left, .right] {
            let frame = SumiReaderControlsLayout.toolbarFrame(in: bounds, safeAreaInsets: .zero,
                avoiding: [fold, camera], side: side, size: CGSize(width: 420, height: 56))
            #expect(!frame.intersects(fold))
            #expect(!frame.intersects(camera))
            #expect(frame.height == 56 && frame.width > 156)
            #expect(bounds.contains(frame))
            if side == .left { #expect(frame.midX < bounds.midX) }
            else { #expect(frame.midX > bounds.midX) }
        }
    }

    @Test("Small portrait windows compress the strip inside the actual safe margins")
    func narrowPortrait() {
        let bounds = CGRect(x: 0, y: 0, width: 280, height: 600)
        let frame = SumiReaderControlsLayout.toolbarFrame(in: bounds,
            safeAreaInsets: UIEdgeInsets(top: 20, left: 28, bottom: 21, right: 42), avoiding: [],
            side: nil, size: CGSize(width: 420, height: 56))
        #expect(frame.minX >= 28 && frame.maxX <= 238)
        #expect(frame.width == 210 && frame.height == 56)
    }

    @Test("An active fold keeps a centered request inside one reachable bottom pane")
    func centeredFoldFallback() {
        let bounds = CGRect(x: 0, y: 0, width: 660, height: 350)
        let fold = CGRect(x: 324, y: 0, width: 12, height: 350)
        let frame = SumiReaderControlsLayout.toolbarFrame(in: bounds, safeAreaInsets: .zero,
            avoiding: [fold], side: nil, size: CGSize(width: 420, height: 56))
        #expect(!frame.intersects(fold))
        #expect(frame.width <= 316 && frame.height == 56)
        #expect(bounds.insetBy(dx: 8, dy: 8).contains(frame))
    }
}
