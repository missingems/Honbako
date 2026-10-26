@testable import Sumi
import Testing
import UIKit

@MainActor
struct ReaderPaperGeometryTests {
    @Test("Reader fore-edges are square while only the binding edge curves")
    func matchingCorners() {
        let leaf = CGRect(x: 0, y: 0, width: 400, height: 700)
        let single = CGRect(x: 0, y: 0, width: 800, height: 700)
        #expect(ReaderBookSpineView.cornerRadius(in: leaf) == ReaderBookSpineView.cornerRadius(in: single))
        #expect(ReaderBookSpineView.cornerRadius(in: leaf) == 0)
        for edge in [ReaderBookSpineView.BindingEdge.none, .left, .right] {
            let path = ReaderBookSpineView.pagePath(in: leaf, bindingEdge: edge)
            #expect(path.contains(CGPoint(x: 200, y: 350)))
            #expect(path.contains(CGPoint(x: 0.1, y: 0.1)) == (edge != .left))
            #expect(path.contains(CGPoint(x: 399.9, y: 0.1)) == (edge != .right))
            #expect(path.contains(CGPoint(x: 0.1, y: 699.9)) == (edge != .left))
            #expect(path.contains(CGPoint(x: 399.9, y: 699.9)) == (edge != .right))
        }
    }

    @Test("Binding clearance is symmetric negative space in the paper shape")
    func symmetricBinding() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 700)
        let left = ReaderBookSpineView.pagePath(in: frame, bindingEdge: .left)
        let right = ReaderBookSpineView.pagePath(in: frame, bindingEdge: .right)
        for x in stride(from: 0.25, through: 399.75, by: 3.5) {
            for y in [0.25, 2.0, 10.0, 27.0, 350.0, 690.0, 699.75] {
                #expect(left.contains(CGPoint(x: x, y: y)) == right.contains(CGPoint(x: 400 - x, y: y)))
            }
        }
        #expect(!left.contains(CGPoint(x: 0.25, y: 350)))
        #expect(!right.contains(CGPoint(x: 399.75, y: 350)))
        #expect(left.contains(CGPoint(x: 2, y: 350)))
        #expect(right.contains(CGPoint(x: 398, y: 350)))
        #expect(!left.contains(CGPoint(x: 4, y: 0.25)))
        #expect(!left.contains(CGPoint(x: 4, y: 699.75)))
        #expect(left.contains(CGPoint(x: 4, y: 350)))
        // The centre is a curved cut into each paper shoulder, not a rounded
        // rectangle or an outline painted down the full height.
        let curve = ReaderBookSpineView.bindingCurve(in: frame)
        #expect(curve.flare == 8)
        #expect(curve.length == 8)
    }

    @Test("Invalid and tiny viewports produce safe finite paths")
    func invalidAndTinyBounds() {
        for frame in [CGRect.zero, .null, .infinite, CGRect(x: 0, y: 0, width: -1, height: 100)] {
            #expect(ReaderBookSpineView.cornerRadius(in: frame) == 0)
            #expect(ReaderBookSpineView.pagePath(in: frame).isEmpty ||
                    ReaderBookSpineView.pagePath(in: frame).boundingBoxOfPath.isEmpty)
        }
        let tiny = CGRect(x: 0, y: 0, width: 2, height: 3)
        let path = ReaderBookSpineView.pagePath(in: tiny, bindingEdge: .left)
        #expect(path.boundingBoxOfPath.width > 0)
        #expect(path.contains(CGPoint(x: 1, y: 1.5)))
    }
}
