@testable import Sumi
import Testing
import UIKit

@MainActor
struct SumiReaderToolbarTests {
    private func descendants<T: UIView>(_ view: UIView, type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type: type) }
    }

    @Test("Close, page previews, and chapters have independent material surfaces")
    func separatedHorizontalControls() throws {
        let toolbar = SumiReaderToolbar(frame: CGRect(x: 0, y: 0, width: 420, height: 48))
        let scrubber = SumiPageScrubber()
        scrubber.update(chapterKey: "one", totalPages: 6, currentPage: 3)
        toolbar.mount(scrubber)
        toolbar.setVisible(true, animated: false)
        toolbar.layoutIfNeeded()
        let surfaces = toolbar.subviews.compactMap { $0 as? UIVisualEffectView }
        #expect(surfaces.count == 3)
        #expect(surfaces.allSatisfy { $0.effect is UIGlassEffect })
        #expect(surfaces[0].frame.maxX + 6 <= surfaces[1].frame.minX)
        #expect(surfaces[1].frame.maxX + 6 <= surfaces[2].frame.minX)
        #expect(!toolbar.point(inside: CGPoint(x: 51, y: 24), with: nil))
        #expect(surfaces[0].bounds.height == 48 && surfaces[2].bounds.height == 48)
        #expect(surfaces[1].bounds.height == 40)
        #expect(toolbar.hitTest(CGPoint(x: 200, y: 1), with: nil) is UICollectionView)
        #expect(surfaces[1].layer.cornerRadius == 13)
        #expect(surfaces[0].layer.cornerRadius == 24 && surfaces[2].layer.cornerRadius == 24)
        #expect(descendants(surfaces[1], type: SumiPageScrubber.self).first === scrubber)
        #expect(descendants(toolbar, type: UIButton.self).allSatisfy { $0.isPointerInteractionEnabled })
        #expect(scrubber.usesSharedToolbarGlass)
        #expect(scrubber.axis == .horizontal)
        #expect(toolbar.bounds.insetBy(dx: -1, dy: -1).contains(scrubber.convert(scrubber.bounds, to: toolbar)))
        #expect(toolbar.chaptersAnchorView.accessibilityIdentifier == "Sumi.Reader.ChaptersButton")
        let glass = try #require(descendants(toolbar, type: UIVisualEffectView.self)
            .first { $0.accessibilityIdentifier == "Sumi.Reader.Scrubber.Glass" })
        #expect(glass.effect is UIGlassEffect)
        #expect(descendants(scrubber, type: UIVisualEffectView.self)
            .filter { $0.accessibilityIdentifier != "Sumi.Reader.PagePosition" && !($0 is SumiScrubHoverGlassView) }
            .allSatisfy { $0.effect == nil || $0.isHidden })
        let hoverGlass = try #require(descendants(scrubber, type: SumiScrubHoverGlassView.self).first)
        #expect(hoverGlass.superview?.isHidden == true, "The added glass belongs only to a lifted preview, never the resting rail")
    }

    @Test("Separate vertical controls keep artwork upright and preserve the hover coordinate space")
    func uprightVerticalContents() throws {
        let toolbar = SumiReaderToolbar(frame: CGRect(x: 0, y: 0, width: 48, height: 380))
        toolbar.axis = .vertical
        toolbar.sidebarEdge = .left
        let scrubber = SumiPageScrubber()
        toolbar.mount(scrubber)
        toolbar.setVisible(true, animated: false)
        toolbar.layoutIfNeeded()
        #expect(scrubber.axis == .vertical)
        #expect(scrubber.sidebarEdge == .left)
        let frame = scrubber.convert(scrubber.bounds, to: toolbar)
        #expect(abs(frame.width - 40) < 0.01)
        #expect(abs(frame.height - 272) < 0.01)
        let surfaces = toolbar.subviews.compactMap { $0 as? UIVisualEffectView }
        #expect(surfaces[0].bounds.width == 48 && surfaces[2].bounds.width == 48)
        #expect(surfaces[1].bounds.width == 40)
        #expect(toolbar.hitTest(CGPoint(x: 1, y: 180), with: nil) is UICollectionView)
        #expect(toolbar.subviews.first { $0.accessibilityIdentifier == "Sumi.Reader.Scrubber.Glass" }?.layer.cornerRadius == 13)
        #expect(toolbar.bounds.insetBy(dx: -1, dy: -1).contains(frame))
        let anchor = toolbar.chaptersAnchorView
        let center = anchor.convert(CGPoint(x: anchor.bounds.midX, y: anchor.bounds.midY), to: toolbar)
        let top = anchor.convert(CGPoint(x: anchor.bounds.midX, y: anchor.bounds.midY - 10), to: toolbar)
        #expect(abs(top.x - center.x) < 0.01)
        #expect(top.y < center.y)
    }

    @Test("The reader-hosted preview follows all three controls during their fade")
    func overlayVisibility() throws {
        let reader = UIView(frame: CGRect(x: 0, y: 0, width: 700, height: 600))
        let toolbar = SumiReaderToolbar(frame: CGRect(x: 640, y: 100, width: 56, height: 380))
        reader.addSubview(toolbar)
        let scrubber = SumiPageScrubber()
        scrubber.previewContainer = reader
        toolbar.mount(scrubber)
        toolbar.setVisible(true, animated: false)
        let overlay = try #require(scrubber.accessibilityOverlayView)
        toolbar.alpha = 0.4
        #expect(abs(overlay.alpha - 0.4) < 0.000001)
        toolbar.setVisible(false, animated: false)
        #expect(overlay.isHidden)
        #expect(toolbar.isHidden)
        let glass = try #require(descendants(toolbar, type: UIVisualEffectView.self)
            .first { $0.accessibilityIdentifier == "Sumi.Reader.Scrubber.Glass" })
        #expect(glass.effect == nil)
    }

    @Test("Control group adapts without shrinking the close and chapter touch targets")
    func adaptiveMetrics() {
        let toolbar = SumiReaderToolbar()
        #expect(toolbar.preferredSize(availableLength: 900) == CGSize(width: 420, height: 48))
        #expect(toolbar.preferredSize(availableLength: 330) == CGSize(width: 330, height: 48))
        toolbar.expandsHorizontalStrip = true
        #expect(toolbar.preferredSize(availableLength: 900) == CGSize(width: 620, height: 48))
        #expect(toolbar.preferredSize(availableLength: 330) == CGSize(width: 330, height: 48))
        toolbar.axis = .vertical
        #expect(toolbar.preferredSize(availableLength: 900) == CGSize(width: 48, height: 380))
        #expect(toolbar.preferredSize(availableLength: 310) == CGSize(width: 48, height: 310))
    }
}
