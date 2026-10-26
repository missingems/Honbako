//
//  ReaderDictionaryGeometryTests.swift
//  AidokuTests
//

@testable import Aidoku
import Testing
import UIKit

@MainActor
struct ReaderDictionaryGeometryTests {
    @Test("Clipped book characters keep matching indices without origin highlights")
    func clippedCharacterHighlights() {
        let visible = CGRect(x: 500, y: 250, width: 20, height: 30)
        let characters: [CGRect] = [.zero, visible, .null]
        #expect(ReaderDictionaryCoordinator.lookupHighlightRects(charRects: characters, matchedCount: 1).isEmpty)
        #expect(ReaderDictionaryCoordinator.lookupHighlightRects(charRects: characters, matchedCount: 2) == [visible.insetBy(dx: -2, dy: -2)])
        #expect(ReaderDictionaryCoordinator.lookupHighlightRects(charRects: characters, matchedCount: 3) == [visible.insetBy(dx: -2, dy: -2)])
    }

    @Test("Hidden bars preserve each asymmetric safe edge")
    func asymmetricSafeEdges() throws {
        let frame = try #require(ReaderDictionaryCoordinator.availablePopupFrame(
            in: CGRect(x: 0, y: 0, width: 700, height: 600),
            safeAreaInsets: UIEdgeInsets(top: 20, left: 80, bottom: 30, right: 4),
            barsHidden: true,
            anchorRect: CGRect(x: 300, y: 300, width: 20, height: 20),
            avoiding: []
        ))
        #expect(frame == CGRect(x: 80, y: 20, width: 608, height: 550))
    }

    @Test("A dictionary popup stays on the selection side of a vertical fold")
    func foldSide() throws {
        let bounds = CGRect(x: 0, y: 0, width: 700, height: 600)
        let fold = CGRect(x: 340, y: 0, width: 20, height: 600)
        for anchorX: CGFloat in [100, 500] {
            let frame = try #require(ReaderDictionaryCoordinator.availablePopupFrame(
                in: bounds,
                safeAreaInsets: .zero,
                barsHidden: true,
                anchorRect: CGRect(x: anchorX, y: 300, width: 20, height: 20),
                avoiding: [fold]
            ))
            #expect(!frame.intersects(fold))
            #expect(frame.contains(CGPoint(x: anchorX, y: 300)))
        }
    }

    @Test("Camera regions are excluded and a fully reserved view has no popup space")
    func occlusion() throws {
        let bounds = CGRect(x: 0, y: 0, width: 700, height: 600)
        let camera = CGRect(x: 600, y: 0, width: 100, height: 120)
        let frame = try #require(ReaderDictionaryCoordinator.availablePopupFrame(
            in: bounds,
            safeAreaInsets: .zero,
            barsHidden: true,
            anchorRect: CGRect(x: 500, y: 300, width: 20, height: 20),
            avoiding: [camera]
        ))
        #expect(!frame.intersects(camera))
        #expect(ReaderDictionaryCoordinator.availablePopupFrame(
            in: bounds,
            safeAreaInsets: .zero,
            barsHidden: true,
            anchorRect: .zero,
            avoiding: [bounds]
        ) == nil)
    }

    @Test("Full-width and tall dictionary layouts stay within an offset safe region")
    func popupFitsOffsetRegion() {
        let frame = CGRect(x: 360, y: 120, width: 328, height: 200)
        for isFullWidth in [false, true] {
            let layout = PopupLayout(
                selectionRect: CGRect(x: 500, y: 180, width: 20, height: 40),
                availableFrame: frame,
                maxWidth: 320,
                maxHeight: 350,
                isVertical: true,
                isFullWidth: isFullWidth
            )
            let popup = CGRect(
                x: layout.position.x - layout.width / 2,
                y: layout.position.y - layout.height / 2,
                width: layout.width,
                height: layout.height
            )
            #expect(frame.contains(popup))
            #expect(popup.height == 188)
        }
    }
}
