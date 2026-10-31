#if SUMI
import Foundation
import Nuke

/// A requested retry explicitly bypasses both HTTP and Nuke image caches.
/// Use this only for an explicit retry or the single source-recovery attempt.
enum SumiPageImageRetryRequest {
    static func make(from request: ImageRequest) -> ImageRequest {
        var retry = request
        if var transport = request.urlRequest {
            transport.cachePolicy = .reloadIgnoringLocalCacheData
            retry = ImageRequest(urlRequest: transport, processors: request.processors,
                priority: request.priority, options: request.options, userInfo: request.userInfo)
            retry.imageID = request.imageID
            retry.scale = request.scale
            retry.thumbnail = request.thumbnail
        }
        retry.options.insert(.reloadIgnoringCachedData)
        return retry
    }
}
#endif
