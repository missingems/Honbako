//
//  ReaderPagePrefetcher.swift
//  Aidoku
//
//  Created by Amqx on 8/26/26.
//

import AidokuRunner
import Foundation
import Nuke

/// Fetches page image data into the disk cache before a page view exists to display them.
@MainActor
final class ReaderPagePrefetcher {
    private let prefetcher: ImagePrefetcher
    private let decodesImages: Bool

    init(decodedImages: Bool = false, pipeline: ImagePipeline = .shared) {
        decodesImages = decodedImages
        prefetcher = ImagePrefetcher(pipeline: pipeline,
            destination: decodedImages ? .memoryCache : .diskCache, maxConcurrentRequestCount: 2)
    }

    /// The number of pages already handed to the prefetcher, per chapter key.
    private var prefetchedCounts: [String: Int] = [:]
    /// Incremented on reset, to drop fetches that were being prepared at the time.
    private var generation = 0

    /// Fetch the first `count` pages of a chapter, skipping any that were already requested.
    func prefetch(pages: [Page], count: Int, chapterKey: String, sourceKey: String,
                  downsampleWidth: CGFloat? = nil, displayScale: CGFloat? = nil) async {
        let target = min(count, pages.count)
        let start = prefetchedCounts[chapterKey] ?? 0
        guard target > start else { return }
        // mark these as requested up front, since building the requests suspends
        prefetchedCounts[chapterKey] = target

        let generation = generation
        let source = await SourceManager.shared.source(for: sourceKey)

        var requests: [ImageRequest] = []
        for page in pages[start..<target] {
            guard
                page.image == nil,
                page.zipURL == nil,
                let imageURL = page.imageURL,
                let url = URL(string: imageURL),
                decodesImages || !url.isFileURL
            else { continue }
            requests.append(await ReaderPageView.imageRequest(url: url, context: page.context, source: source,
                downsampleWidth: downsampleWidth, displayScale: displayScale))
        }

        guard !requests.isEmpty, generation == self.generation else { return }
        prefetcher.startPrefetching(with: requests)
    }

    /// Cancel outstanding fetches and forget what's been requested.
    func reset() {
        generation += 1
        prefetcher.stopPrefetching()
        prefetchedCounts.removeAll()
    }
}
