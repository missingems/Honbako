#if SUMI
import Foundation

struct HonbakoRecommendationFeed: Decodable, Sendable {
    struct Item: Decodable, Identifiable, Sendable, Equatable {
        let id: String
        let title: String
        let authors: [String]
        let year: Int?
        let status: String
        let coverURL: URL?
        let officialURL: URL?
        let searchQuery: String
        let reason: String

        var isValid: Bool {
            !id.isEmpty && id.count <= 160 && !title.isEmpty && title.count <= 300
                && !searchQuery.isEmpty && searchQuery.count <= 300 && authors.count <= 30
                && [coverURL, officialURL].compactMap { $0 }.allSatisfy(Self.isPublicHTTPS)
        }

        static func isPublicHTTPS(_ url: URL) -> Bool {
            guard url.scheme == "https", let host = url.host?.lowercased(), !host.isEmpty,
                  url.user == nil, url.password == nil else { return false }
            return host != "localhost" && !host.hasSuffix(".local") && !host.hasSuffix(".internal")
                && host != "127.0.0.1" && host != "0.0.0.0" && host != "::1"
        }
    }

    let schemaVersion: Int
    let generatedAt: Date
    let items: [Item]

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 512 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let feed = try decoder.decode(Self.self, from: data)
        guard feed.schemaVersion == 1, feed.items.count <= 200,
              feed.items.allSatisfy(\.isValid), Set(feed.items.map(\.id)).count == feed.items.count else {
            throw URLError(.cannotParseResponse)
        }
        return feed
    }
}
#endif
