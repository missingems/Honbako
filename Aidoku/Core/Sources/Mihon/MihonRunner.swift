import AidokuRunner
import CryptoKit
import Foundation

/// Lazy bytes are the required image-loader integration seam. Existing Runner
/// only supplies URLRequests; fetching those URLs directly would bypass the
/// extension's getImage implementation. Nuke's async-data ImageRequest and the
/// download worker must use this provider before this source can be installed.
protocol MihonRuntimeImageProviding: Sendable {
    func runtimeImageData(url: URL, context: AidokuRunner.PageContext?) async throws -> MihonRuntimeImagePayload
}

actor MihonRunner: AidokuRunner.Runner, MihonRuntimeImageProviding, MihonRuntimeCoverImageProviding {
    struct Configuration: Equatable, Sendable {
        let extensionURL: URL
        let packageName: String
        let versionName: String
        let packageSHA256: String
        let sourceID: String
        let language: String
        let baseURL: URL?
        let preferences: [String: String]
        var sourceKey: String { "mihon.\(sourceID)" }

        init(extensionURL: URL, packageName: String, versionName: String, packageSHA256: String,
             sourceID: String, language: String, baseURL: URL? = nil, preferences: [String: String] = [:]) throws {
            guard extensionURL.isFileURL, extensionURL.pathExtension.lowercased() == "jar",
                  extensionURL.query == nil, extensionURL.fragment == nil,
                  !packageName.isEmpty, packageName.utf8.count <= 512,
                  !versionName.isEmpty, versionName.utf8.count <= 512, !language.isEmpty, language.utf8.count <= 64,
                  packageSHA256.count == 64, packageSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  (try? MihonRepositoryCatalog.exactID(sourceID)) == sourceID,
                  preferences.count <= 256, preferences.allSatisfy({ $0.key.utf8.count <= 1024 && $0.value.utf8.count <= 16_384 }) else {
                throw MihonRuntimeError.invalidConfiguration
            }
            if let baseURL { _ = try MihonRepositoryCatalog.requiredURL(baseURL.absoluteString, relativeTo: baseURL, metadata: true) }
            self.extensionURL = extensionURL
            self.packageName = packageName
            self.versionName = versionName
            self.packageSHA256 = packageSHA256
            self.sourceID = sourceID
            self.language = language
            self.baseURL = baseURL
            self.preferences = preferences
        }
    }

    nonisolated let features = AidokuRunner.SourceFeatures(providesImageRequests: true)
    nonisolated let configuration: Configuration
    nonisolated var runtimeCoverSourceKey: String { configuration.sourceKey }
    nonisolated let runtimeCoverCacheScope: String
    private let transport: any MihonRuntimeTransport
    private var verified = false
    private var issuedPages: Set<String> = []
    private var issuedPageOrder: [String] = []
    private let contextKey = "honbako.mihon.page.v1"
    static let maximumMetadataBytes = 8 * 1024 * 1024
    static let maximumImageBytes = 32 * 1024 * 1024
    static let imageScheme = "honbako-mihon-page"

    init(configuration: Configuration, transport: any MihonRuntimeTransport) {
        self.configuration = configuration
        self.transport = transport
        self.runtimeCoverCacheScope = Self.makeScope(configuration)
    }

    private var session: MihonRuntimeSession {
        .init(extensionPath: configuration.extensionURL.path, sourceId: configuration.sourceID, preferences: configuration.preferences)
    }

    func getSearchMangaList(query: String?, page: Int, filters: [AidokuRunner.FilterValue]) async throws -> AidokuRunner.MangaPageResult {
        try Task.checkCancellation()
        guard filters.isEmpty else { throw MihonRuntimeError.unsupportedFilters }
        guard page > 0, page <= Int(Int32.max), (query?.utf8.count ?? 0) <= 16_384 else { throw MihonRuntimeError.invalidInput }
        try await verifySource()
        let result: SearchResult = try await execute(.init(session: session, operation: .search, query: query ?? "", page: page))
        guard result.entries.count <= 4_096 else { throw MihonRuntimeError.payloadTooLarge }
        let entries = try result.entries.map(manga)
        try Task.checkCancellation()
        return .init(entries: entries, hasNextPage: result.hasNextPage)
    }

    func getMangaUpdate(manga input: AidokuRunner.Manga, needsDetails: Bool, needsChapters: Bool) async throws -> AidokuRunner.Manga {
        try Task.checkCancellation()
        try validate(input)
        guard needsDetails || needsChapters else { return input }
        try await verifySource()
        var output = input
        if needsDetails {
            let result: UpdateResult = try await execute(.init(session: session, operation: .details, manga: record(output)))
            guard result.manga.url == input.key else { throw MihonRuntimeError.identityMismatch }
            let details = try manga(result.manga)
            output.title = details.title
            output.cover = details.cover ?? output.cover
            output.authors = details.authors ?? output.authors
            output.artists = details.artists ?? output.artists
            output.description = details.description ?? output.description
            output.url = details.url
            output.status = details.status
        }
        if needsChapters {
            let result: UpdateResult = try await execute(.init(session: session, operation: .chapters, manga: record(output)))
            guard result.manga.url == input.key else { throw MihonRuntimeError.identityMismatch }
            guard result.chapters.count <= 32_000 else { throw MihonRuntimeError.payloadTooLarge }
            var seen: Set<String> = []
            output.chapters = try result.chapters.map { chapter in
                guard seen.insert(chapter.url).inserted else { throw MihonRuntimeError.invalidWireResponse }
                return try self.chapter(chapter)
            }
        }
        try Task.checkCancellation()
        return output
    }

    func getPageList(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) async throws -> [AidokuRunner.Page] {
        try Task.checkCancellation()
        try validate(manga)
        try validateKey(chapter.key)
        try await verifySource()
        let result: PageResult = try await execute(.init(session: session, operation: .pages,
            chapter: .init(url: chapter.key, name: chapter.title ?? "", number: nil, uploadedAt: nil, scanlator: nil)))
        guard result.pages.count <= 4_096 else { throw MihonRuntimeError.payloadTooLarge }
        let pages: [AidokuRunner.Page] = try result.pages.enumerated().map { position, page in
            guard page.index >= 0, page.index <= Int(Int32.max) else { throw MihonRuntimeError.invalidWireResponse }
            if !page.url.isEmpty { try validateKey(page.url) }
            if let imageURL = page.imageUrl, !imageURL.isEmpty { try validateKey(imageURL) }
            guard !page.url.isEmpty || page.imageUrl?.isEmpty == false else { throw MihonRuntimeError.invalidWireResponse }
            let descriptor = ImageDescriptor(sourceID: configuration.sourceID, scope: scope(),
                mangaKey: manga.key, chapterKey: chapter.key, position: position, page: page)
            let data = try encoder().encode(descriptor)
            guard data.count <= 64 * 1024 else { throw MihonRuntimeError.payloadTooLarge }
            let url = opaqueURL(data)
            if issuedPages.insert(url.absoluteString).inserted { issuedPageOrder.append(url.absoluteString) }
            return .init(content: .url(url: url, context: [contextKey: data.base64EncodedString()]))
        }
        if issuedPageOrder.count > 16_384 {
            let expired = issuedPageOrder.count - 16_384
            for key in issuedPageOrder.prefix(expired) { issuedPages.remove(key) }
            issuedPageOrder.removeFirst(expired)
        }
        try Task.checkCancellation()
        return pages
    }

    /// Generic URLRequest loading is deliberately unavailable for runtime pages.
    /// Their synthetic scheme fails closed if an older loader misses this seam.
    func getImageRequest(url: String, context: AidokuRunner.PageContext?) async throws -> URLRequest {
        throw MihonRuntimeError.imageLoaderRequired
    }

    func runtimeImageData(url: URL, context: AidokuRunner.PageContext?) async throws -> MihonRuntimeImagePayload {
        try Task.checkCancellation()
        guard url.scheme == Self.imageScheme, issuedPages.contains(url.absoluteString),
              let encoded = context?[contextKey], encoded.utf8.count <= 90_000,
              let data = Data(base64Encoded: encoded), data.count <= 64 * 1024,
              let descriptor = try? JSONDecoder().decode(ImageDescriptor.self, from: data),
              descriptor.sourceID == configuration.sourceID, descriptor.scope == scope(),
              opaqueURL(data) == url else { throw MihonRuntimeError.invalidPageContext }
        try validateKey(descriptor.mangaKey)
        try validateKey(descriptor.chapterKey)
        guard descriptor.position >= 0, descriptor.position < 4_096,
              descriptor.page.index >= 0, descriptor.page.index <= Int(Int32.max) else { throw MihonRuntimeError.invalidPageContext }
        if !descriptor.page.url.isEmpty { try validateKey(descriptor.page.url) }
        if let imageURL = descriptor.page.imageUrl, !imageURL.isEmpty { try validateKey(imageURL) }
        guard !descriptor.page.url.isEmpty || descriptor.page.imageUrl?.isEmpty == false else { throw MihonRuntimeError.invalidPageContext }
        try await verifySource()
        let image = try await transport.imageData(.init(session: session, page: descriptor.page))
        try Task.checkCancellation()
        guard !image.data.isEmpty else { throw MihonRuntimeError.invalidImage }
        guard image.data.count <= Self.maximumImageBytes else { throw MihonRuntimeError.payloadTooLarge }
        if let count = image.reportedByteCount, count != image.data.count { throw MihonRuntimeError.invalidImage }
        if let digest = image.reportedSHA256 {
            guard digest == Self.digest(image.data) else { throw MihonRuntimeError.invalidImage }
        }
        if let type = image.mediaType {
            guard type.utf8.count <= 256,
                  type.lowercased().hasPrefix("image/") || type.lowercased().split(separator: ";").first == "application/octet-stream",
                  !type.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { throw MihonRuntimeError.invalidImage }
        }
        try Task.checkCancellation()
        return image
    }

    func runtimeCoverData(url: URL) async throws -> MihonRuntimeImagePayload {
        try Task.checkCancellation()
        try validateKey(url.absoluteString)
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else {
            throw MihonRuntimeError.invalidInput
        }
        guard let coverTransport = transport as? any MihonRuntimeCoverTransport else {
            throw MihonRuntimeError.imageLoaderRequired
        }
        try await verifySource()
        let image = try await coverTransport.coverData(session: session, url: url)
        try Task.checkCancellation()
        guard !image.data.isEmpty else { throw MihonRuntimeError.invalidImage }
        guard image.data.count <= Self.maximumImageBytes else { throw MihonRuntimeError.payloadTooLarge }
        if let count = image.reportedByteCount, count != image.data.count { throw MihonRuntimeError.invalidImage }
        if let hash = image.reportedSHA256, hash != Self.digest(image.data) { throw MihonRuntimeError.invalidImage }
        if let type = image.mediaType {
            let normalized = type.lowercased().split(separator: ";").first.map(String.init) ?? ""
            guard type.utf8.count <= 256,
                  !type.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
                  normalized.hasPrefix("image/") || normalized == "application/octet-stream" else { throw MihonRuntimeError.invalidImage }
        }
        try Task.checkCancellation()
        return image
    }

    private func verifySource() async throws {
        try Task.checkCancellation()
        if verified { return }
        let result: Discovery = try await execute(.init(session: session, operation: .discover))
        guard result.package == configuration.packageName, result.version == configuration.versionName,
              result.sources.count <= 1_024,
              let source = result.sources.first(where: { $0.id == configuration.sourceID }),
              result.sources.filter({ $0.id == configuration.sourceID }).count == 1,
              !source.name.isEmpty,
              source.language.lowercased().replacingOccurrences(of: "_", with: "-")
                == configuration.language.lowercased().replacingOccurrences(of: "_", with: "-") else {
            throw MihonRuntimeError.identityMismatch
        }
        try Task.checkCancellation()
        verified = true
    }

    private func execute<Result: Decodable & Sendable>(_ request: MihonRuntimeRequest) async throws -> Result {
        try Task.checkCancellation()
        let data = try await transport.execute(request)
        try Task.checkCancellation()
        guard data.count <= Self.maximumMetadataBytes else { throw MihonRuntimeError.payloadTooLarge }
        let envelope: Envelope<Result>
        do { envelope = try JSONDecoder().decode(Envelope<Result>.self, from: data) }
        catch { throw MihonRuntimeError.invalidWireResponse }
        guard envelope.ok else {
            throw MihonRuntimeError.extensionFailure(type: envelope.errorType, message: envelope.error ?? "Extension operation failed.")
        }
        guard envelope.error == nil, envelope.errorType == nil, let result = envelope.result else { throw MihonRuntimeError.invalidWireResponse }
        return result
    }

    private func manga(_ record: MihonRuntimeMangaRecord) throws -> AidokuRunner.Manga {
        try validateKey(record.url)
        guard !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              record.title.utf8.count <= 16_384 else { throw MihonRuntimeError.invalidWireResponse }
        let cover = try record.cover.flatMap { raw -> String? in
            guard !raw.isEmpty else { return nil }
            try validateKey(raw)
            return try publicURL(raw)?.absoluteString
        }
        let status: AidokuRunner.PublishingStatus = switch record.status {
            case 1: .ongoing
            case 2, 4: .completed
            case 5: .cancelled
            case 6: .hiatus
            default: .unknown
        }
        return try .init(sourceKey: configuration.sourceKey, key: record.url, title: record.title, cover: cover,
            artists: nonempty(record.artist).map { [$0] }, authors: nonempty(record.author).map { [$0] },
            description: record.description, url: publicURL(record.url), status: status, contentRating: .unknown, viewer: .unknown)
    }

    private func chapter(_ record: MihonRuntimeChapterRecord) throws -> AidokuRunner.Chapter {
        try validateKey(record.url)
        var number: Float?
        if let value = record.number, value >= 0 {
            guard value.isFinite, value <= Double(Float.greatestFiniteMagnitude) else { throw MihonRuntimeError.invalidWireResponse }
            number = Float(value)
        }
        var date: Date?
        if let milliseconds = record.uploadedAt, milliseconds > 0 {
            guard milliseconds <= 253_402_300_799_999 else { throw MihonRuntimeError.invalidWireResponse }
            date = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
        }
        let language = ["all", "multi"].contains(configuration.language.lowercased()) ? nil : configuration.language
        return try .init(key: record.url, title: nonempty(record.name), chapterNumber: number,
            dateUploaded: date, scanlators: nonempty(record.scanlator).map { [$0] }, url: publicURL(record.url), language: language)
    }

    private func record(_ manga: AidokuRunner.Manga) -> MihonRuntimeMangaRecord { .init(url: manga.key, title: manga.title) }
    private func nonempty(_ value: String?) -> String? { value.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } }
    private func validate(_ manga: AidokuRunner.Manga) throws {
        guard manga.sourceKey == configuration.sourceKey else { throw MihonRuntimeError.identityMismatch }
        try validateKey(manga.key)
    }
    private func validateKey(_ key: String) throws {
        guard !key.isEmpty, key.utf8.count <= 16_384,
              !key.contains("\\"), !key.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
              let url = URL(string: key), url.user == nil, url.password == nil else { throw MihonRuntimeError.invalidWireResponse }
        if let scheme = url.scheme {
            guard ["http", "https"].contains(scheme.lowercased()), url.host?.isEmpty == false else { throw MihonRuntimeError.invalidWireResponse }
        }
    }
    private func publicURL(_ key: String) throws -> URL? {
        guard let absolute = URL(string: key), absolute.scheme == nil || ["http", "https"].contains(absolute.scheme?.lowercased() ?? "") else {
            throw MihonRuntimeError.invalidWireResponse
        }
        if absolute.scheme != nil { return absolute }
        guard let base = configuration.baseURL else { return nil }
        return try MihonRepositoryCatalog.resolvedURL(key, relativeTo: base, metadata: true)
    }
    private nonisolated func scope() -> String { runtimeCoverCacheScope }
    private nonisolated static func makeScope(_ configuration: Configuration) -> String {
        let values = [configuration.packageSHA256, configuration.packageName, configuration.versionName,
            configuration.extensionURL.path, configuration.sourceID, configuration.language]
        var data = (values.joined(separator: "\n")).data(using: .utf8) ?? Data()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        if let preferences = try? encoder.encode(configuration.preferences) { data.append(preferences) }
        return Self.digest(data)
    }
    private func opaqueURL(_ data: Data) -> URL {
        URL(string: "\(Self.imageScheme)://runtime/\(configuration.sourceID)/\(Self.digest(data))")!
    }
    private nonisolated func encoder() -> JSONEncoder { let result = JSONEncoder(); result.outputFormatting = [.sortedKeys]; return result }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private struct ImageDescriptor: Codable {
        let sourceID: String
        let scope: String
        let mangaKey: String
        let chapterKey: String
        let position: Int
        let page: MihonRuntimePageRecord
    }
    private struct Envelope<Result: Decodable>: Decodable {
        let ok: Bool
        let result: Result?
        let errorType: String?
        let error: String?
    }
    private struct Discovery: Decodable, Sendable {
        let package: String
        let version: String
        let sources: [Source]
        struct Source: Decodable, Sendable { let id: String; let name: String; let language: String }
    }
    private struct SearchResult: Decodable, Sendable { let entries: [MihonRuntimeMangaRecord]; let hasNextPage: Bool }
    private struct UpdateResult: Decodable, Sendable { let manga: MihonRuntimeMangaRecord; let chapters: [MihonRuntimeChapterRecord] }
    private struct PageResult: Decodable, Sendable { let pages: [MihonRuntimePageRecord] }
}
