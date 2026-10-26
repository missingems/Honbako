@testable import Sumi
import Foundation
import Testing

struct HonbakoRecommendationFeedTests {
    private func feed(official: String = "https://www.viz.com/example", duplicate: Bool = false) -> Data {
        let item = """
        {"id":"one","title":"Title","authors":["Author"],"year":2020,"status":"ongoing",
        "coverURL":null,"officialURL":"\(official)","searchQuery":"Title","reason":"A suggestion"}
        """
        return Data("""
        {"schemaVersion":1,"generatedAt":"2026-10-26T12:00:00Z","items":[\(item)\(duplicate ? "," + item : "")]}
        """.utf8)
    }

    @Test("Recommendation metadata retains search intent without adding source or library entries")
    func metadataOnly() throws {
        let result = try HonbakoRecommendationFeed.decode(feed())
        #expect(result.items.count == 1)
        #expect(result.items[0].searchQuery == "Title")
        #expect(result.items[0].coverURL == nil)
        #expect(result.items[0].officialURL?.host == "www.viz.com")
    }

    @Test("A damaged or unsafe remote catalog cannot replace validated suggestions")
    func unsafeCatalogs() {
        for url in ["file:///private/data", "http://example.com/book", "https://localhost/book", "https://user:password@example.com/book"] {
            #expect(throws: URLError.self) { try HonbakoRecommendationFeed.decode(feed(official: url)) }
        }
        #expect(throws: URLError.self) { try HonbakoRecommendationFeed.decode(feed(duplicate: true)) }
        #expect(throws: URLError.self) { try HonbakoRecommendationFeed.decode(Data(repeating: 0, count: 512 * 1024 + 1)) }
    }
}
