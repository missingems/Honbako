#if SUMI && DEBUG
import Foundation

/// Explicit, simulator-only marketing data. The licensed excerpts are seeded in
/// the test app's Documents directory, never bundled with the shipping app.
struct HonbakoLicensedMarketingSample: Decodable {
    struct Book: Decodable {
        let key: String
        let japaneseTitle: String
        let volume: Int
        let cover: String
        let pages: [String]
    }
    let author: String
    let books: [Book]
    var directory: URL {
        URL.documentsDirectory.appending(path: "HonbakoLicensedSample", directoryHint: .isDirectory)
    }
    static func load() -> Self? {
        guard SumiGridPreviewFixtures.usesLicensedMarketingSample else { return nil }
        let url = URL.documentsDirectory.appending(path: "HonbakoLicensedSample/manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}
#endif
