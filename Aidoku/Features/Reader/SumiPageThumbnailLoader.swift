#if SUMI
import AidokuRunner
import Nuke
import UIKit

/// Bounded previews reuse the page request rules, including source headers and
/// page processors. Only the filmstrip's visible samples and selected page load.
@MainActor
final class SumiPageThumbnailLoader {
    private let cache = NSCache<NSString, UIImage>()
    private let temporaryStore = ReaderTemporaryPageStore()
    private let mangaKey: String

    init(mangaKey: String = "") {
        self.mangaKey = mangaKey
        cache.countLimit = 48
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func image(for page: Page, position: Int, source: AidokuRunner.Source?, forHover: Bool = false) async -> UIImage? {
        // Source-converted pages may still carry the legacy default index zero.
        // The reader's canonical ordinal is the identity of a thumbnail.
        let artwork = page.image.map { String(ObjectIdentifier($0).hashValue) } ?? page.imageURL ?? ""
        let identity = "sumi-preview-v5-leaf|\(page.sourceId)|\(mangaKey)|\(page.chapterId)|\(page.index)|\(position)|\(artwork)"
        let key = "\(identity)|\(forHover ? "hover" : "strip")" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image: UIImage?
        if let existing = page.image {
            image = await SumiPreviewCropper.shared.prepare(existing, forHover: forHover)
        } else if let raw = page.base64, let data = Data(base64Encoded: raw) {
            if let decoded = UIImage(data: data) { image = await SumiPreviewCropper.shared.prepare(decoded, forHover: forHover) }
            else { image = nil }
        } else {
            let url: URL?
            if let archive = page.zipURL, let archiveURL = URL(string: archive), let path = page.imageURL {
                url = await temporaryStore.storeArchiveEntry(from: archiveURL, path: path)
            } else if let raw = page.imageURL, let original = URL(string: raw) {
                url = original.toAidokuFileUrl() ?? original
            } else { url = nil }
            guard let url, !Task.isCancelled else { return nil }
            var request = await ReaderPageView.imageRequest(url: url, context: page.context, source: source)
            request.imageID = "\(identity)|\(request.imageID ?? url.absoluteString)"
            // Preview resolution is independent from the reader's image options.
            request.processors = request.processors.filter { !($0 is UpscaleProcessor) && !($0 is DownsampleProcessor) }
            request.processors.append(SumiPreviewCropper.thumbnailProcessor(forHover: forHover))
            request.priority = forHover ? .normal : .low
            let fetch = SumiPageImageFetch()
            image = try? await fetch.response(for: request).image
        }
        guard !Task.isCancelled else { return nil }
        guard let image else { return nil }
        let cropped = await SumiPreviewCropper.shared.crop(image)
        guard !Task.isCancelled else { return nil }
        cache.setObject(cropped, forKey: key, cost: (cropped.cgImage?.bytesPerRow ?? 0) * (cropped.cgImage?.height ?? 0))
        return cropped
    }

    deinit {
        let store = temporaryStore
        Task { await store.removeAll() }
    }
}
#endif
