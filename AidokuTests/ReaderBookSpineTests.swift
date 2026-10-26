@testable import Aidoku
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct ReaderBookSpineTests {
    @Test("Binding follows the actual page seam and shared artwork height in either order")
    func artworkSeam() throws {
        let left = CGRect(x: 40, y: 20, width: 280, height: 600)
        let right = CGRect(x: 320, y: 80, width: 400, height: 500)
        let frame = try #require(ReaderBookSpineView.frame(between: [left, right]))
        #expect(frame.midX == 320)
        #expect(frame.minY == 80)
        #expect(frame.maxY == 580)
        #expect(frame.width < 40)
        #expect(ReaderBookSpineView.frame(between: [right, left]) == frame)
        #expect(ReaderBookSpineView.frame(between: [left]) == nil)
        #expect(ReaderBookSpineView.frame(between: [left, .zero]) == nil)
        #expect(ReaderBookSpineView.frame(between: [left, right.offsetBy(dx: 0, dy: 1000)]) == nil)
    }

    @Test("Binding is decorative and resets when the book layout is unavailable")
    func decorativeAndReset() {
        let spine = ReaderBookSpineView()
        #expect(!spine.isUserInteractionEnabled)
        #expect(!spine.isAccessibilityElement)
        #expect(spine.accessibilityElementsHidden)
        spine.update(pageFrames: [CGRect(x: 0, y: 0, width: 200, height: 400),
                                  CGRect(x: 200, y: 0, width: 200, height: 400)], enabled: true)
        #expect(!spine.isHidden)
        #expect(!spine.frame.isEmpty)
        spine.update(pageFrames: [], enabled: false)
        #expect(spine.isHidden)
        #expect(spine.frame == .zero)
    }

    @Test("Curved binding widens at the paper ends, stays narrow in the middle, and preserves surrounding ink")
    func renderedBinding() throws {
        let paper = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        paper.backgroundColor = .white
        let ink = UIView(frame: CGRect(x: 0, y: 110, width: 320, height: 20))
        ink.backgroundColor = .black
        paper.addSubview(ink)
        let spine = ReaderBookSpineView()
        paper.addSubview(spine)
        spine.update(pageFrames: [CGRect(x: 0, y: 0, width: 160, height: 240),
                                  CGRect(x: 160, y: 0, width: 160, height: 240)], enabled: true)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        paper.layoutIfNeeded()
        spine.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: paper.bounds.size, format: format).image { context in
            paper.layer.render(in: context.cgContext)
        }
        let cgImage = try #require(image.cgImage)
        var rgba = [UInt8](repeating: 0, count: 320 * 240 * 4)
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 320, height: 240,
                                          bitsPerComponent: 8, bytesPerRow: 320 * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: paper.bounds)
            return true
        }
        #expect(rendered)
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let start = (y * 320 + x) * 4
            return Array(rgba[start..<(start + 4)])
        }
        let crease = pixel(160, 30)
        #expect(crease[0] == 0)
        #expect(crease[0] == crease[1] && crease[1] == crease[2])
        #expect(pixel(20, 30) == [255, 255, 255, 255])
        #expect(pixel(160, 120) == [0, 0, 0, 255])
        #expect(pixel(157, 3)[0] < 70)
        #expect(pixel(162, 3)[0] < 70)
        #expect(pixel(157, 60) == [255, 255, 255, 255])
        #expect(pixel(162, 60) == [255, 255, 255, 255])
    }

    @Test("The real spread keeps its spine outside arranged pages and hides it in portrait")
    func spreadLifecycle() async throws {
        let store = ReaderTemporaryPageStore()
        defer { Task { await store.removeAll() } }
        let first = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: store)
        let second = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: store)
        let spread = ReaderDoublePageViewController(firstPage: first, secondPage: second, direction: .ltr)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        window.rootViewController = spread
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        spread.viewWillAppear(false)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 500)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 500))
        }
        let pages = try [first, second].map { try #require($0.pageView) }
        for page in pages { page.imageView.image = image; page.fixImageSize() }
        func settle() {
            for _ in 0..<4 {
                window.setNeedsLayout(); spread.view.setNeedsLayout()
                window.layoutIfNeeded(); spread.view.layoutIfNeeded()
            }
        }
        settle()
        let stack = try #require(spread.zoomView.zoomView as? UIStackView)
        let spine = try #require(stack.subviews.compactMap { $0 as? ReaderBookSpineView }.first)
        #expect(stack.arrangedSubviews.count == 2)
        #expect(!spine.isHidden)
        #expect(!stack.arrangedSubviews.contains(spine))
        #expect(pages.allSatisfy { $0.imageView.image === image })
        spread.direction = .rtl
        settle()
        #expect(stack.arrangedSubviews.count == 2)
        #expect(!spine.isHidden)
        #expect(stack.subviews.last === spine)
        window.frame.size = CGSize(width: 700, height: 1000)
        settle()
        #expect(spine.isHidden)
        #expect(spine.frame.isEmpty)
    }
}
