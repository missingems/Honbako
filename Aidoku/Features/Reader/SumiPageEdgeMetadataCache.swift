#if SUMI
import Foundation

/// Keep thousands of compact color results independently of decoded bitmaps.
/// Re-decoding the same request can reuse its metadata after image eviction.
final class SumiPageEdgeMetadataCache: @unchecked Sendable {
    static let shared = SumiPageEdgeMetadataCache()

    private final class Entry {
        let colors: [String: SumiPageEdgeColors]
        init(_ colors: [String: SumiPageEdgeColors]) { self.colors = colors }
    }

    private let entries: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 2048
        cache.totalCostLimit = 2 * 1024 * 1024
        return cache
    }()

    private let lock = NSLock()
    private var preparedImages = 0
    private var reusedMetadata = 0
    private var readyViewReads = 0

    func colors(for key: String) -> [String: SumiPageEdgeColors]? {
        guard let colors = entries.object(forKey: key as NSString)?.colors else { return nil }
        lock.lock(); reusedMetadata += 1; lock.unlock()
        return colors
    }

    func store(_ colors: [String: SumiPageEdgeColors], for key: String) {
        entries.setObject(Entry(colors), forKey: key as NSString, cost: 128 + colors.count * 128)
    }

    func recordPreparedImage() {
        lock.lock(); preparedImages += 1; lock.unlock()
    }

    func recordReadyViewRead() {
        lock.lock(); readyViewReads += 1; lock.unlock()
    }

    func status() -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return ["preparedImages": preparedImages, "reusedMetadata": reusedMetadata,
                "readyViewReads": readyViewReads]
    }
}
#endif
