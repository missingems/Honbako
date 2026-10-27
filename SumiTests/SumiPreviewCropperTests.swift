@testable import Sumi
import Testing
import UIKit

@MainActor
struct SumiPreviewCropperTests {
    private func image(background: UIColor, ink: CGRect? = nil) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300), format: format).image { context in
            background.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
            if let ink { UIColor.black.setFill(); context.fill(ink) }
        }
    }

    @Test("Preview cropping removes verified blank margins on all four sides")
    func trimsWhiteMargins() async throws {
        let original = image(background: .white, ink: CGRect(x: 20, y: 40, width: 160, height: 200))
        let result = await SumiPreviewCropper.shared.crop(original)
        #expect(result.size == CGSize(width: 162, height: 202))
        #expect(original.size == CGSize(width: 200, height: 300))
        // Top and bottom margins deliberately differ (40 and 60 pixels).
        // Compare actual encoded pixels against a source-coordinate crop,
        // rather than accepting an upside-down crop with the same dimensions.
        let expectedPixels = try #require(original.cgImage?.cropping(to:
            CGRect(x: 19, y: 39, width: 162, height: 202)))
        let expected = UIImage(cgImage: expectedPixels, scale: 1, orientation: .up)
        #expect(result.pngData() == expected.pngData(),
                "The complete original ink must survive between one-pixel white margins on every edge")
    }

    @Test("Blank white pages and solid black pages retain their complete composition")
    func preservesBlankAndBlackPages() async {
        for color in [UIColor.white, .black] {
            let original = image(background: color)
            #expect(await SumiPreviewCropper.shared.crop(original) === original)
        }
    }

    @Test("Ink touching a page edge cannot be trimmed as a blank margin")
    func preservesEdgeInk() async {
        let original = image(background: .white, ink: CGRect(x: 0, y: 40, width: 180, height: 200))
        let result = await SumiPreviewCropper.shared.crop(original)
        #expect(result.size == CGSize(width: 181, height: 202))
    }

    @Test("Cropped preview caching leaves the reader's actual page bitmap unchanged")
    func loaderDoesNotChangeActualPage() async throws {
        let original = image(background: .white, ink: CGRect(x: 20, y: 40, width: 160, height: 200))
        let bytes = original.pngData()
        let page = Sumi.Page(sourceId: "crop", chapterId: "chapter", image: original)
        let loader = SumiPageThumbnailLoader(mangaKey: "manga")
        let preview = try #require(await loader.image(for: page, position: 1, source: nil))
        #expect(preview.size.width / preview.size.height > original.size.width / original.size.height)
        #expect(page.image === original)
        #expect(page.image?.pngData() == bytes)
        #expect(SumiSpreadThumbnailView().backgroundColor == .clear)
    }

    @Test("A large hover loads detailed artwork without reusing the filmstrip's small cached image")
    func hoverUsesDetailedCacheTier() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let original = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1800), format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1800))
        }
        let page = Sumi.Page(sourceId: "detail", chapterId: "chapter", image: original)
        let loader = SumiPageThumbnailLoader(mangaKey: "manga")
        let strip = try #require(await loader.image(for: page, position: 1, source: nil))
        let hover = try #require(await loader.image(for: page, position: 1, source: nil, forHover: true))
        #expect(strip.cgImage?.width == 240 && strip.cgImage?.height == 360)
        #expect(hover.cgImage?.width == 720 && hover.cgImage?.height == 1080)
        #expect(await loader.image(for: page, position: 1, source: nil) === strip)
        #expect(await loader.image(for: page, position: 1, source: nil, forHover: true) === hover)
        #expect(page.image === original)
    }

    @Test("A tall page keeps a detailed center crop instead of first shrinking its full height")
    func tallPageCropsBeforeDownsampling() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let original = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 7200), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 240, height: 7200))
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 3420, width: 240, height: 360))
        }
        let page = Sumi.Page(sourceId: "tall", chapterId: "chapter", image: original)
        let loader = SumiPageThumbnailLoader(mangaKey: "manga")
        let preview = try #require(await loader.image(for: page, position: 1, source: nil))
        #expect(preview.size == CGSize(width: 240, height: 360),
                "The preview must retain source-width detail rather than enlarging a few-pixel-wide thumbnail")
        let bitmap = try #require(preview.cgImage)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: bitmap.width, height: bitmap.height,
            bitsPerComponent: 8, bytesPerRow: bitmap.width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        let pixels = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
        for point in [(0, 0), (bitmap.width - 1, bitmap.height - 1), (bitmap.width / 2, bitmap.height / 2)] {
            let offset = point.1 * context.bytesPerRow + point.0 * 4
            #expect(pixels[offset] < 10 && pixels[offset + 1] < 10 && pixels[offset + 2] > 245,
                    "Every preview edge should show the center blue panel, not the full page's red surroundings")
        }
        #expect(page.image === original)
        #expect(original.size == CGSize(width: 240, height: 7200))
    }
}
