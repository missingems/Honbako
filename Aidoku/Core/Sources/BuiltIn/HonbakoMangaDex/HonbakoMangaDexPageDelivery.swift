#if SUMI
import AidokuRunner
import Foundation

/// The chapter and canonical page survive an @Home host change. Page URLs are
/// temporary delivery addresses and must not be the identity used for a retry.
struct HonbakoMangaDexPageDelivery: Sendable {
    static let chapterKey = "honbako.mangadex.chapter"
    static let pageKey = "honbako.mangadex.page"
    static let fileKey = "honbako.mangadex.file"
    static let lifetime: TimeInterval = 10 * 60
    static let recoveryCooldown: TimeInterval = 5

    let response: HonbakoMangaDexAPI.PageServer
    let resolvedAt: Date
    var recoveredAt: Date?

    func pages(chapterID: String) throws -> [AidokuRunner.Page] {
        try response.pages().enumerated().map { index, page in
            guard case .url(let url, _) = page.content else { return page }
            return .init(content: .url(url: url, context: [
                Self.chapterKey: chapterID,
                Self.pageKey: String(index),
                Self.fileKey: response.chapter.data[index]
            ]))
        }
    }

    func url(at index: Int) throws -> URL? {
        let pages = try response.pages()
        guard pages.indices.contains(index), case .url(let url, _) = pages[index].content else { return nil }
        return url
    }

    static func identity(url: URL, context: PageContext?) -> (chapterID: String, index: Int)? {
        guard let context, let chapterID = context[chapterKey], UUID(uuidString: chapterID) != nil,
              let rawIndex = context[pageKey], let index = Int(rawIndex), (0..<512).contains(index),
              let originalFile = context[fileKey], HonbakoMangaDexAPI.safePathComponent(originalFile),
              url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        let parts = url.pathComponents
        guard parts.count >= 4, parts[parts.count - 3] == "data",
              HonbakoMangaDexAPI.safePathComponent(parts[parts.count - 2]),
              HonbakoMangaDexAPI.safePathComponent(url.lastPathComponent) else { return nil }
        return (chapterID, index)
    }

    static func imageRequest(url: URL, reload: Bool) -> URLRequest {
        var request = URLRequest(url: url,
            cachePolicy: reload ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy,
            timeoutInterval: 30)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue("https://mangadex.org/", forHTTPHeaderField: "Referer")
        request.setValue("Honbako/0.2 (https://github.com/missingems/Honbako)", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        return request
    }
}
#endif
