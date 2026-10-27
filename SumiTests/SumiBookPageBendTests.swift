@testable import Sumi
import Testing
import UIKit

@MainActor
struct SumiBookPageBendTests {
    @Test("Settled artwork curves at the binding while its outer print remains exactly unchanged")
    func localCurvatureAndMirror() {
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 600)
        for y: CGFloat in [0, 40, 300, 560, 600] {
            let outer = CGPoint(x: 220, y: y)
            #expect(SumiBookPageBendGeometry.point(outer, in: bounds, edge: .left) == outer)
            let source = CGPoint(x: 20, y: y)
            let left = SumiBookPageBendGeometry.point(source, in: bounds, edge: .left)
            let right = SumiBookPageBendGeometry.point(CGPoint(x: bounds.width - source.x, y: y), in: bounds, edge: .right)
            #expect(left.x < source.x)
            #expect(abs(left.x + right.x - bounds.width) < 0.0001)
            #expect(abs(left.y - right.y) < 0.0001)
            if y < bounds.midY { #expect(left.y > y) }
            if y > bounds.midY { #expect(left.y < y) }
            #expect(SumiBookPageBendGeometry.point(source, in: bounds, edge: .none) == source)
        }
    }

    @Test("The shallow mesh keeps source order with no folded-over strips or missing texture ranges")
    func boundedMonotonicMesh() {
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 600)
        var last: CGFloat = -1
        for step in 0...1000 {
            let x = CGFloat(step) * bounds.width / 1000
            let sample = SumiBookPageBendGeometry.point(CGPoint(x: x, y: 0), in: bounds, edge: .left)
            #expect(sample.x > last)
            #expect(sample.y >= 0 && sample.y <= 14)
            last = sample.x
        }
        for edge in [ReaderBookSpineView.BindingEdge.left, .right] {
            let ranges = (0..<SumiBookPageBendGeometry.stripCount).map {
                SumiBookPageBendGeometry.textureRange(strip: $0, edge: edge)
            }.sorted { $0.lowerBound < $1.lowerBound }
            #expect(ranges.first?.lowerBound == 0 && ranges.last?.upperBound == 1)
            for pair in zip(ranges, ranges.dropFirst()) { #expect(pair.0.upperBound == pair.1.lowerBound) }
        }
    }

    @Test("Both affine faces preserve the exact projected corners of every paper strip")
    func triangleProjection() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 480)
        for edge in [ReaderBookSpineView.BindingEdge.left, .right] {
            for strip in 0..<SumiBookPageBendGeometry.stripCount {
                let range = SumiBookPageBendGeometry.textureRange(strip: strip, edge: edge)
                let left = range.lowerBound * bounds.width
                let right = range.upperBound * bounds.width
                let corners = [CGPoint(x: left, y: 0), CGPoint(x: right, y: 0),
                    CGPoint(x: right, y: bounds.height), CGPoint(x: left, y: bounds.height)]
                for indices in [[0, 1, 3], [1, 2, 3]] {
                    let source = indices.map { corners[$0] }
                    let target = source.map { SumiBookPageBendGeometry.point($0, in: bounds, edge: edge) }
                    let affine = SumiBookPageBendGeometry.affine(from: source, to: target)
                    for pair in zip(source, target) {
                        let result = pair.0.applying(affine)
                        #expect(abs(result.x - pair.1.x) < 0.0001)
                        #expect(abs(result.y - pair.1.y) < 0.0001)
                    }
                }
            }
        }
    }

    @Test("The mesh reuses one snapshot for identical layouts and releases it immediately for portrait or loading")
    func cacheAndReset() throws {
        let (source, native, bend, image) = surface()
        bend.update(image: image, animated: false, ready: true, edge: .left,
            source: source, nativeImage: native, imageFrame: native.frame)
        #expect(bend.isPrepared && native.isHidden && !bend.isHidden)
        #expect(bend.snapshotCount == 1)
        let strips = try #require(bend.layer.sublayers)
        #expect(strips.count == 1, "The settled mesh retains one baked texture, not per-frame projective layers")
        let first = try #require(strips.first?.contents as AnyObject?)
        #expect(strips.allSatisfy { ($0.contents as AnyObject?) === first })
        for _ in 0..<10 {
            bend.update(image: image, animated: false, ready: true, edge: .left,
                source: source, nativeImage: native, imageFrame: native.frame)
        }
        #expect(bend.snapshotCount == 1, "Repeated layout cannot render another bitmap")
        source.bounds.size.height += 40
        native.frame = source.bounds
        bend.update(image: image, animated: false, ready: true, edge: .left,
            source: source, nativeImage: native, imageFrame: native.frame)
        #expect(bend.snapshotCount == 2)
        bend.update(image: image, animated: false, ready: true, edge: .none,
            source: source, nativeImage: native, imageFrame: native.frame)
        #expect(!bend.isPrepared && !native.isHidden && bend.isHidden)
        #expect(strips.allSatisfy { $0.contents == nil })
        bend.update(image: image, animated: true, ready: true, edge: .left,
            source: source, nativeImage: native, imageFrame: native.frame)
        #expect(!bend.isPrepared && !native.isHidden, "GIFs must keep their native animation")
        bend.update(image: image, animated: false, ready: false, edge: .left,
            source: source, nativeImage: native, imageFrame: native.frame)
        #expect(!bend.isPrepared && !native.isHidden, "The loading fade stays on the native image")
    }

    @Test("The existing curl layer-snapshot path captures curved ink, rather than a flat or empty print")
    func layerSnapshotContainsBentArtwork() throws {
        let (source, native, bend, image) = surface()
        bend.update(image: image, animated: false, ready: true, edge: .left,
            source: source, nativeImage: native, imageFrame: native.frame)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let captured = UIGraphicsImageRenderer(size: source.bounds.size, format: format).image { context in
            source.layer.render(in: context.cgContext)
        }
        let bent = SumiBookPageBendGeometry.point(CGPoint(x: 20, y: 41), in: source.bounds, edge: .left)
        #expect(try brightness(image, at: bent) > 220)
        #expect(try brightness(captured, at: bent) < 100, "A curl snapshot must contain the moved ink, not only the gutter gradient")
        #expect(try brightness(captured, at: CGPoint(x: 220, y: 41)) < 100, "Outer print keeps its exact baseline")
    }

    @Test("A real loaded page keeps readiness and canonical image identity, then drops the bend on portrait and clear")
    func pageLifecycle() async throws {
        let store = ReaderTemporaryPageStore()
        defer { Task { await store.removeAll() } }
        let page = ReaderPageView(temporaryPageStore: store)
        page.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        let image = artwork()
        page.bookBindingEdge = .left
        page.setPageImage(image)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !page.sumiIsImageReady, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        page.setNeedsLayout(); page.layoutIfNeeded()
        #expect(page.sumiHasSettledBookBend)
        #expect(page.sumiIsImageReady && page.imageView.image === image)
        page.bookBindingEdge = .none
        #expect(!page.sumiHasSettledBookBend && !page.imageView.isHidden)
        page.frame.size = CGSize(width: 480, height: 800)
        page.setNeedsLayout(); page.layoutIfNeeded()
        #expect(!page.sumiHasSettledBookBend && page.imageView.image === image)
        page.bookBindingEdge = .right
        page.setNeedsLayout(); page.layoutIfNeeded()
        #expect(page.sumiHasSettledBookBend)
        page.setPageImage(nil)
        #expect(!page.sumiHasSettledBookBend && !page.imageView.isHidden && !page.sumiIsImageReady)
    }

    private func surface() -> (UIView, UIImageView, SumiBookPageBendView, UIImage) {
        let image = artwork()
        let source = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        source.backgroundColor = .white
        let native = UIImageView(image: image); native.frame = source.bounds
        source.addSubview(native)
        let bend = SumiBookPageBendView(); source.addSubview(bend)
        return (source, native, bend, image)
    }

    private func artwork() -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 320, height: 480), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 480))
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 40, width: 320, height: 3))
        }
    }

    private func brightness(_ image: UIImage, at point: CGPoint) throws -> Int {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let pixel = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { _ in
            image.draw(at: CGPoint(x: -point.x.rounded(), y: -point.y.rounded()))
        }
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(try #require(pixel.cgImage), in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let data = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
        return (Int(data[0]) + Int(data[1]) + Int(data[2])) / 3
    }
}
