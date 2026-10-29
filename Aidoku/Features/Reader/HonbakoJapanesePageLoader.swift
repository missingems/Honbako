#if SUMI
import AidokuRunner
import Nuke
import UIKit

/// Load the original page rather than the cropped, low-resolution filmstrip
/// preview. Source request headers and page unscrambling remain intact.
@MainActor
final class HonbakoJapanesePageLoader {
    private let temporaryStore = ReaderTemporaryPageStore()

    func image(for page: Page, source: AidokuRunner.Source?) async -> UIImage? {
        guard !Task.isCancelled, page.type == .imagePage, !page.isTextPage else { return nil }
        if let image = page.image { return image }
        if let base64 = page.base64 {
            let image = await Task.detached(priority: .userInitiated) {
                Data(base64Encoded: base64).flatMap(UIImage.init(data:))
            }.value
            return Task.isCancelled ? nil : image
        }
        let url: URL?
        if let rawArchive = page.zipURL, let archive = URL(string: rawArchive), let path = page.imageURL {
            url = await temporaryStore.storeArchiveEntry(from: archive, path: path)
        } else if let rawURL = page.imageURL, let original = URL(string: rawURL) {
            url = original.toAidokuFileUrl() ?? original
        } else { url = nil }
        guard let url, !Task.isCancelled else { return nil }
        var request = await ReaderPageView.imageRequest(url: url, context: page.context, source: source)
        request.processors = request.processors.filter {
            !($0 is DownsampleProcessor) && !($0 is UpscaleProcessor) && !($0 is SumiPageEdgePreparationProcessor)
        }
        request.priority = .normal
        let image = try? await ImagePipeline.shared.image(for: request)
        return Task.isCancelled ? nil : image
    }

    deinit {
        let store = temporaryStore
        Task { await store.removeAll() }
    }
}
#endif
