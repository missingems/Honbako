import Foundation

/// A transport owns execution/cancellation of the runtime, not source identity
/// or app persistence. The app target does not yet provide a JNI implementation.
protocol MihonRuntimeTransport: Sendable {
    func execute(_ request: MihonRuntimeRequest) async throws -> Data
    /// Fetches one image through the extension's image service, preserving its
    /// URL-resolution and HTTP hooks. A JNI byte[] boundary can avoid base64.
    func imageData(_ request: MihonRuntimeImageRequest) async throws -> MihonRuntimeImagePayload
}

struct MihonRuntimeSession: Encodable, Equatable, Sendable {
    let extensionPath: String
    let sourceId: String
    /// The verified prototype supports string preferences. Other setting types
    /// need an explicit runtime contract before they can be advertised.
    let preferences: [String: String]
}

struct MihonRuntimeMangaRecord: Codable, Equatable, Sendable {
    let url: String
    let title: String
    var cover: String?
    var author: String?
    var artist: String?
    var description: String?
    var status: Int?
}

struct MihonRuntimeChapterRecord: Codable, Equatable, Sendable {
    let url: String
    let name: String
    var number: Double?
    var uploadedAt: Int64?
    var scanlator: String?
}

struct MihonRuntimePageRecord: Codable, Equatable, Sendable {
    let index: Int
    let url: String
    /// Nil is meaningful: the extension must resolve the image from page.url.
    /// It must never be replaced with a raw HTTP fetch of that page URL.
    let imageUrl: String?
}

struct MihonRuntimeRequest: Encodable, Equatable, Sendable {
    enum Operation: String, Encodable, Sendable { case discover, search, details, chapters, pages }
    let session: MihonRuntimeSession
    let operation: Operation
    var query: String?
    var page: Int?
    var manga: MihonRuntimeMangaRecord?
    var chapter: MihonRuntimeChapterRecord?

    private enum CodingKeys: String, CodingKey { case extensionPath, sourceId, preferences, operation, query, page, manga, chapter }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(session.extensionPath, forKey: .extensionPath)
        try values.encode(session.sourceId, forKey: .sourceId)
        try values.encode(session.preferences, forKey: .preferences)
        try values.encode(operation, forKey: .operation)
        try values.encodeIfPresent(query, forKey: .query)
        try values.encodeIfPresent(page, forKey: .page)
        try values.encodeIfPresent(manga, forKey: .manga)
        try values.encodeIfPresent(chapter, forKey: .chapter)
    }
}

struct MihonRuntimeImageRequest: Encodable, Equatable, Sendable {
    let session: MihonRuntimeSession
    let page: MihonRuntimePageRecord
    private enum CodingKeys: String, CodingKey { case extensionPath, sourceId, preferences, operation, page, includeData }
    /// Matches the current JSON bridge. A binary JNI transport can consume the
    /// typed request directly and return the same image payload without JSON.
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(session.extensionPath, forKey: .extensionPath)
        try values.encode(session.sourceId, forKey: .sourceId)
        try values.encode(session.preferences, forKey: .preferences)
        try values.encode("image", forKey: .operation)
        try values.encode(page, forKey: .page)
        try values.encode(true, forKey: .includeData)
    }
}

struct MihonRuntimeImagePayload: Equatable, Sendable {
    let data: Data
    let mediaType: String?
    let reportedByteCount: Int?
    let reportedSHA256: String?

    init(data: Data, mediaType: String? = nil, reportedByteCount: Int? = nil, reportedSHA256: String? = nil) {
        self.data = data
        self.mediaType = mediaType
        self.reportedByteCount = reportedByteCount
        self.reportedSHA256 = reportedSHA256
    }
}

enum MihonRuntimeError: Error, Equatable {
    case invalidConfiguration
    case invalidInput
    case invalidWireResponse
    case identityMismatch
    case unsupportedFilters
    case payloadTooLarge
    case imageLoaderRequired
    case invalidPageContext
    case invalidImage
    case extensionFailure(type: String?, message: String)
}
