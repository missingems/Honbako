#if SUMI
import Nuke
import CryptoKit
import Foundation

/// The same processor is used for decoded prefetch and visible page requests.
/// It prepares metadata without changing the original page image or its alpha.
struct SumiPageEdgePreparationProcessor: ImageProcessing, Hashable {
    let cacheIdentity: String
    var identifier: String { "com.missingems.honbako.page-edges.v1.\(cacheIdentity)" }

    init(request: URLRequest, sourceKey: String?, sourceVersion: Int?, pageContext: [String: String]?, processors: [ImageProcessing]) {
        let values: [String: Any] = ["url": request.url?.absoluteString ?? "",
            "headers": request.allHTTPHeaderFields ?? [:], "context": pageContext ?? [:],
            "source": sourceKey ?? "", "version": sourceVersion ?? 0,
            "method": request.httpMethod ?? "GET", "body": request.httpBody.map { SHA256.hash(data: $0).description } ?? "",
            "processors": processors.map(\.identifier)]
        let data = (try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])) ?? Data()
        cacheIdentity = SHA256.hash(data: data).map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
    }

    func process(_ image: PlatformImage) -> PlatformImage? {
        _ = SumiPreparedPageEdges.prepare(image: image, cacheIdentity: cacheIdentity)
        return image
    }

    func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
        if context.isCompleted { _ = SumiPreparedPageEdges.prepare(image: container.image, cacheIdentity: cacheIdentity) }
        return container
    }
}
#endif
