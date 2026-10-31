#if SUMI
import CryptoKit
import UIKit

enum HonbakoPageCoachingImageEncoder {
    struct Encoded: Sendable {
        let image: HonbakoPageCoachingModels.Image
        let contentHash: String
    }

    /// A canonical page bitmap only. Never render a window, app, toolbar, or another scene.
    @MainActor
    static func encode(_ image: UIImage) -> Encoded? {
        guard image.images == nil, image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.height > 0 else { return nil }
        for longestEdge: CGFloat in [1600, 1280, 960, 720] {
            let scale = min(1, longestEdge / max(image.size.width, image.size.height))
            let size = CGSize(width: max(1, floor(image.size.width * scale)), height: max(1, floor(image.size.height * scale)))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            for quality in [0.78, 0.60, 0.42] {
                guard let data = rendered.jpegData(compressionQuality: quality),
                      data.count <= HonbakoPageCoachingPolicy.maximumImageBytes else { continue }
                return Encoded(image: .init(mimeType: "image/jpeg", data: data.base64EncodedString(),
                    width: Int(size.width), height: Int(size.height)),
                    contentHash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            }
        }
        return nil
    }
}
#endif
