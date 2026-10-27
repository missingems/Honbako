#if SUMI
import AidokuRunner
import Foundation

/// First-party mappings written against MangaDex's public OpenAPI schema.
/// No source extension implementation or executable is bundled here.
enum HonbakoMangaDexAPI {
    struct Collection<Item: Decodable & Sendable>: Decodable, Sendable {
        let result: String
        let data: [Item]
        let limit: Int
        let offset: Int
        let total: Int
    }

    struct Entity<Item: Decodable & Sendable>: Decodable, Sendable {
        let result: String
        let data: Item
    }

    struct Relationship: Decodable, Sendable {
        let id: String
        let type: String
        let attributes: Attributes?

        struct Attributes: Decodable, Sendable {
            let name: String?
            let fileName: String?
        }
    }

    struct Title: Decodable, Sendable {
        let id: String
        let attributes: Attributes
        let relationships: [Relationship]?

        struct Attributes: Decodable, Sendable {
            let title: [String: String]
            let description: [String: String]?
            let year: Int?
            let status: String?
            let contentRating: String?
            let availableTranslatedLanguages: [String?]?
            let tags: [Tag]?
        }

        struct Tag: Decodable, Sendable {
            let attributes: Attributes
            struct Attributes: Decodable, Sendable { let name: [String: String] }
        }

        var translatedLanguages: [String] {
            Array(Set((attributes.availableTranslatedLanguages ?? []).compactMap { $0 }
                .filter(isValidLanguage).map(canonicalLanguage))).sorted()
        }

        func manga(preferredLanguages: [String]) -> AidokuRunner.Manga {
            let relationships = relationships ?? []
            let authorNames = relationships.filter { $0.type == "author" }.compactMap { $0.attributes?.name }
            let artistNames = relationships.filter { $0.type == "artist" }.compactMap { $0.attributes?.name }
            let coverFile = relationships.first { $0.type == "cover_art" }?.attributes?.fileName
            let cover = coverFile.flatMap { fileName -> String? in
                    guard safePathComponent(fileName) else { return nil }
                    return "https://uploads.mangadex.org/covers/\(id)/\(fileName).256.jpg"
            }
            let status: AidokuRunner.PublishingStatus = switch attributes.status {
                case "ongoing": .ongoing
                case "completed": .completed
                case "cancelled": .cancelled
                case "hiatus": .hiatus
                default: .unknown
            }
            let rating: AidokuRunner.ContentRating = switch attributes.contentRating {
                case "safe": .safe
                case "suggestive": .suggestive
                case "erotica", "pornographic": .nsfw
                default: .unknown
            }
            let longStrip = attributes.tags?.contains {
                $0.attributes.name["en"]?.lowercased().split(whereSeparator: \.isWhitespace).joined() == "longstrip"
            } == true
            return .init(sourceKey: HonbakoMangaDexRunner.sourceKey, key: id,
                title: localized(attributes.title, languages: preferredLanguages) ?? "Untitled",
                cover: cover, artists: artistNames.isEmpty ? nil : artistNames,
                authors: authorNames.isEmpty ? nil : authorNames,
                description: attributes.description.flatMap { localized($0, languages: preferredLanguages) },
                url: URL(string: "https://mangadex.org/title/\(id)"),
                tags: attributes.tags?.compactMap { localized($0.attributes.name, languages: preferredLanguages) },
                status: status, contentRating: rating, viewer: longStrip ? .webtoon : .rightToLeft)
        }
    }

    struct Chapter: Decodable, Sendable {
        let id: String
        let attributes: Attributes
        let relationships: [Relationship]?

        struct Attributes: Decodable, Sendable {
            let title: String?
            let volume: String?
            let chapter: String?
            let pages: Int
            let translatedLanguage: String
            let externalUrl: String?
            let publishAt: String?
            let readableAt: String?
            let isUnavailable: Bool?
        }

        func isReadable(at date: Date) -> Bool {
            guard UUID(uuidString: id) != nil, attributes.pages > 0,
                  attributes.externalUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
                  attributes.isUnavailable != true else { return false }
            return [attributes.publishAt, attributes.readableAt].compactMap(timestamp).allSatisfy { $0 <= date }
        }

        func chapter() -> AidokuRunner.Chapter {
            .init(key: id, title: attributes.title,
                chapterNumber: attributes.chapter.flatMap(Float.init),
                volumeNumber: attributes.volume.flatMap(Float.init),
                dateUploaded: timestamp(attributes.publishAt),
                scanlators: relationships?.filter { $0.type == "scanlation_group" }.compactMap { $0.attributes?.name },
                url: URL(string: "https://mangadex.org/chapter/\(id)"),
                language: canonicalLanguage(attributes.translatedLanguage))
        }
    }

    struct PageServer: Decodable, Sendable {
        let result: String
        let baseUrl: URL
        let chapter: Files

        struct Files: Decodable, Sendable {
            let hash: String
            let data: [String]
        }

        func pages() throws -> [AidokuRunner.Page] {
            guard result == "ok", baseUrl.scheme?.lowercased() == "https", baseUrl.host != nil,
                  baseUrl.user == nil, baseUrl.password == nil, baseUrl.query == nil, baseUrl.fragment == nil,
                  safePathComponent(chapter.hash), !chapter.data.isEmpty, chapter.data.count <= 512,
                  chapter.data.allSatisfy(safePathComponent) else {
                throw HonbakoMangaDexError.invalidResponse
            }
            return chapter.data.map { file in
                let url = baseUrl.appendingPathComponent("data")
                    .appendingPathComponent(chapter.hash).appendingPathComponent(file)
                return .init(content: .url(url: url))
            }
        }
    }

    static func canonicalLanguage(_ code: String) -> String {
        switch code.lowercased().replacingOccurrences(of: "_", with: "-") {
            case "es-la": "es-419"
            case "zh": "zh-hans"
            case "zh-hk": "zh-hant"
            default: code.lowercased().replacingOccurrences(of: "_", with: "-")
        }
    }

    static func apiLanguage(_ code: String) -> String {
        switch canonicalLanguage(code) {
            case "es-419": "es-la"
            case "zh-hans": "zh"
            case "zh-hant": "zh-hk"
            default: canonicalLanguage(code)
        }
    }

    /// The public API specifies a code grammar, not a finite language enum.
    static func isValidLanguage(_ code: String) -> Bool {
        apiLanguage(code).range(of: #"^[a-zA-Z\-]{2,5}$"#, options: .regularExpression) != nil
    }

    static func safePathComponent(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 220 && value != "." && value != ".."
            && value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-")).contains($0)
            }
    }

    private static func localized(_ values: [String: String], languages: [String]) -> String? {
        for language in languages + ["en", "ja", "ja-ro"] {
            if let value = values[apiLanguage(language)] ?? values[language], !value.isEmpty { return value }
        }
        return values.sorted { $0.key < $1.key }.first(where: { !$0.value.isEmpty })?.value
    }

    private static func timestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value))
            ?? (try? Date.ISO8601FormatStyle().parse(value))
    }
}
#endif
