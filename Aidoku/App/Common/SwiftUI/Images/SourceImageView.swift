//
//  SourceImageView.swift
//  Aidoku
//
//  Created by Skitty on 4/26/25.
//

import AidokuRunner
import Nuke
import NukeUI
import SwiftUI

struct SourceImageView: View {
    var source: AidokuRunner.Source?

    let imageUrl: String
    var width: CGFloat?
    var height: CGFloat?
    var downsampleWidth: CGFloat?
    var contentMode: ContentMode = .fill
    var placeholder = "MangaPlaceholder"

    @State private var imageRequest: ImageRequest?

    private struct RequestIdentity: Hashable {
        let url: String
        let source: ObjectIdentifier?
        let runtimeScope: String?
    }

    private var processors: [ImageProcessing] {
        var processors: [ImageProcessing] = []
        if let downsampleWidth {
            processors.append(DownsampleProcessor(width: downsampleWidth))
        }
        let usesRuntimeCover = URL(string: imageUrl).map { MihonRuntimeCoverImageLoader.handles(url: $0, source: source) } ?? false
        if let source, source.features.processesCovers,
           !usesRuntimeCover {
            processors.append(CoverInterceptorProcessor(source: source))
        }
        return processors
    }

    var body: some View {
        LazyImage(
            request: imageRequest,
            transaction: .init(animation: .default)
        ) { state in
            if state.imageContainer?.type == .gif, let data = state.imageContainer?.data {
                GIFImage(
                    data: data,
                    contentMode: contentMode
                )
                    .frame(width: width, height: height)
                    .id(state.image != nil ? imageUrl : "placeholder") // ensures only opacity is animated
            } else {
                let result = if let image = state.image {
                    image
                } else {
                    Image(placeholder)
                }
                result
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: width, height: height)
                    .id(state.image != nil ? imageUrl : "placeholder") // ensures only opacity is animated
            }
        }
        .processors(processors)
        .task(id: RequestIdentity(url: imageUrl, source: source.map(ObjectIdentifier.init),
                                  runtimeScope: MihonRuntimeCoverImageLoader.cacheScope(source: source))) {
            imageRequest = nil
            let request = await Self.makeImageRequest(url: imageUrl, source: source)
            guard !Task.isCancelled else { return }
            imageRequest = request
        }
    }

    static func makeImageRequest(url: String, source: AidokuRunner.Source?) async -> ImageRequest {
        let url = URL(string: url)
        if let fileUrl = url?.toAidokuFileUrl() {
            return ImageRequest(url: fileUrl)
        }
        if let url, let runtime = MihonRuntimeCoverImageLoader.imageRequest(url: url, source: source) {
            return runtime
        }
        guard let source, let url, !url.isFileURL else {
            return ImageRequest(url: url)
        }
        return ImageRequest(
            urlRequest: await source.getModifiedImageRequest(url: url, context: nil),
            userInfo: [.processesKey: source.features.processesCovers]
        )
    }
}
