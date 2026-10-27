#if SUMI
import Foundation
import ObjectiveC
import UIKit

/// Small metadata travels with the decoded page in Nuke's cache. It retains no
/// extra bitmap, cannot match a recycled image address, and survives view reuse.
final class SumiPreparedPageEdges: @unchecked Sendable {
    // Only the address is used by the Objective-C association API.
    nonisolated(unsafe) private static var associationKey: UInt8 = 0
    private let lock = NSLock()
    private var colors: [String: SumiPageEdgeColors] = [:]
    private var contentKey: String?

    static let fullPage = CGRect(x: 0, y: 0, width: 1, height: 1)
    private static let commonCrops = [fullPage,
        CGRect(x: 0, y: 0, width: 0.5, height: 1),
        CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]

    static func cached(image: UIImage, crop: CGRect = fullPage) -> SumiPageEdgeColors? {
        guard let bitmap = image.cgImage ?? image.images?.first?.cgImage,
              let metadata = objc_getAssociatedObject(image, &associationKey) as? SumiPreparedPageEdges,
              metadata.lock.try() else { return nil }
        defer { metadata.lock.unlock() }
        let result = metadata.colors[SumiPageEdgeColors.cropIdentity(image: bitmap, orientation: image.imageOrientation, crop: crop)]
        if result != nil { SumiPageEdgeMetadataCache.shared.recordReadyViewRead() }
        return result
    }

    /// Called by the background image processor before prefetch publishes the
    /// page. Full-page and split-spread margins are ready before either is used.
    static func prepare(image: UIImage, crop: CGRect = fullPage, cacheIdentity: String? = nil) -> SumiPageEdgeColors? {
        guard let bitmap = image.cgImage ?? image.images?.first?.cgImage else { return nil }
        let metadata = metadata(for: image)
        metadata.lock.lock()
        defer { metadata.lock.unlock() }
        if let cacheIdentity {
            let key = "\(cacheIdentity)-\(bitmap.width)x\(bitmap.height)-\(image.imageOrientation.rawValue)"
            metadata.contentKey = key
            if let cached = SumiPageEdgeMetadataCache.shared.colors(for: key) { metadata.colors.merge(cached) { current, _ in current } }
        }
        if metadata.colors.count >= 32 {
            let commonKeys = Set(commonCrops.map {
                SumiPageEdgeColors.cropIdentity(image: bitmap, orientation: image.imageOrientation, crop: $0)
            })
            metadata.colors = metadata.colors.filter { commonKeys.contains($0.key) }
        }
        let wasEmpty = metadata.colors.isEmpty
        for region in commonCrops + [crop] {
            guard !Task.isCancelled else { return nil }
            let key = SumiPageEdgeColors.cropIdentity(image: bitmap, orientation: image.imageOrientation, crop: region)
            if metadata.colors[key] == nil {
                metadata.colors[key] = SumiPageEdgeColors.sample(image: bitmap, orientation: image.imageOrientation, crop: region)
            }
        }
        if wasEmpty, !metadata.colors.isEmpty { SumiPageEdgeMetadataCache.shared.recordPreparedImage() }
        if let key = metadata.contentKey { SumiPageEdgeMetadataCache.shared.store(metadata.colors, for: key) }
        return metadata.colors[SumiPageEdgeColors.cropIdentity(image: bitmap, orientation: image.imageOrientation, crop: crop)]
    }

    private static func metadata(for image: UIImage) -> SumiPreparedPageEdges {
        objc_sync_enter(image)
        defer { objc_sync_exit(image) }
        if let existing = objc_getAssociatedObject(image, &associationKey) as? SumiPreparedPageEdges { return existing }
        let metadata = SumiPreparedPageEdges()
        objc_setAssociatedObject(image, &associationKey, metadata, .OBJC_ASSOCIATION_RETAIN)
        return metadata
    }
}
#endif
