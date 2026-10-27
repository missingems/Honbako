#if SUMI
import Nuke
import UIKit

/// Preview-only resampling and trimming run away from the reader's rendering
/// executor. The bounded output never modifies the source page.
actor SumiPreviewCropper {
    static let shared = SumiPreviewCropper()

    static func thumbnailProcessor(forHover: Bool = false) -> ImageProcessors.Resize {
        ImageProcessors.Resize(size: forHover ? CGSize(width: 720, height: 1080) : CGSize(width: 240, height: 360), unit: .pixels,
                               contentMode: .aspectFill, crop: true)
    }

    func prepare(_ image: UIImage, forHover: Bool = false) -> UIImage {
        guard !Task.isCancelled else { return image }
        // Resize and crop into a bounded output directly from the source. A
        // full-height webtoon thumbnail would discard nearly all horizontal
        // detail before the strip or hover had a chance to crop it.
        return Self.thumbnailProcessor(forHover: forHover).process(image) ?? image
    }

    func crop(_ image: UIImage) -> UIImage {
        guard !Task.isCancelled, let source = image.cgImage else { return image }
        let width = source.width, height = source.height
        guard width >= 16, height >= 16, width <= 4096, height <= 8192,
              width * height <= 4_000_000,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: width * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return image }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            guard !Task.isCancelled else { return image }
            let row = y * context.bytesPerRow
            for x in 0..<width {
                let offset = row + x * 4
                // Black borders and faint text are content. Only verified
                // near-white outer pixels can be removed from this preview.
                if pixels[offset] < 250 || pixels[offset + 1] < 250 || pixels[offset + 2] < 250 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        // A blank white page has no ink boundary. A black page's boundary is
        // already the full bitmap. Both keep their original composition.
        guard maxX >= minX, maxY >= minY else { return image }
        let minimumX = max(2, width / 100), minimumY = max(2, height / 100)
        let left = minX >= minimumX ? max(0, minX - 1) : 0
        let top = minY >= minimumY ? max(0, minY - 1) : 0
        let right = width - 1 - maxX >= minimumX ? min(width, maxX + 2) : width
        let bottom = height - 1 - maxY >= minimumY ? min(height, maxY + 2) : height
        let rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        guard rect != CGRect(x: 0, y: 0, width: width, height: height),
              let cropped = source.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}
#endif
