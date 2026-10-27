import CryptoKit
import Foundation

/// The narrow Swift/native boundary. Executors receive the bridge's flat JSON
/// object; only metadata returns JSON. Image bytes never pass through base64.
///
/// This transport does not authorize a package. Production callers must bind
/// the identity of a reviewed, persisted JAR before handing it to the runtime.
/// The Runner remains responsible for decoding envelopes and source identity.
struct MihonJSONRuntimeTransport: MihonRuntimeTransport {
    typealias JSONExecutor = @Sendable (String) async throws -> String
    typealias ImageExecutor = @Sendable (String) async throws -> MihonRuntimeImagePayload

    struct PackageIdentity: Equatable, Sendable {
        let extensionPath: String
        let packageSHA256: String
        let packageName: String
        let versionName: String
        let extensionLibrary: String

        init(extensionPath: String, packageSHA256: String, packageName: String,
             versionName: String, extensionLibrary: String = "1.6") throws {
            try MihonJSONRuntimeTransport.validatePath(extensionPath)
            guard packageSHA256.utf8.count == 64,
                  packageSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  !packageName.isEmpty, packageName.utf8.count <= 512,
                  !versionName.isEmpty, versionName.utf8.count <= 512,
                  !MihonJSONRuntimeTransport.hasControl(packageName),
                  !MihonJSONRuntimeTransport.hasControl(versionName),
                  extensionLibrary == "1.6" else { throw MihonRuntimeError.invalidConfiguration }
            self.extensionPath = extensionPath
            self.packageSHA256 = packageSHA256
            self.packageName = packageName
            self.versionName = versionName
            self.extensionLibrary = extensionLibrary
        }
    }

    /// Match the native executor's UTF-16 limits before JNI allocation, with a
    /// separate byte bound for Swift's encoded metadata buffers.
    static let maximumRequestBytes = 1024 * 1024
    static let maximumRequestUTF16Units = 524_288
    static let maximumResponseUTF16Units = 4_194_304
    static let maximumMetadataBytes = MihonRunner.maximumMetadataBytes
    static let maximumImageBytes = MihonRunner.maximumImageBytes

    private let executeJSON: JSONExecutor
    private let imageBytes: ImageExecutor
    let packageIdentity: PackageIdentity?

    init(packageIdentity: PackageIdentity? = nil,
         executeJSON: @escaping JSONExecutor, imageBytes: @escaping ImageExecutor) {
        self.packageIdentity = packageIdentity
        self.executeJSON = executeJSON
        self.imageBytes = imageBytes
    }

    func execute(_ request: MihonRuntimeRequest) async throws -> Data {
        try Task.checkCancellation()
        try validate(request.session)
        try Self.validate(request)
        let input = try encoded(request)
        try Task.checkCancellation()
        let output: String
        do { output = try await executeJSON(input) }
        catch { try Task.checkCancellation(); throw error }
        try Task.checkCancellation()
        guard output.utf16.count <= Self.maximumResponseUTF16Units,
              output.utf8.count <= Self.maximumMetadataBytes else { throw MihonRuntimeError.payloadTooLarge }
        // Do not translate a bridge error envelope here. The Runner decodes the
        // operation-specific result and its error envelope in one place.
        let data = Data(output.utf8)
        try Task.checkCancellation()
        return data
    }

    func imageData(_ request: MihonRuntimeImageRequest) async throws -> MihonRuntimeImagePayload {
        try Task.checkCancellation()
        try validate(request.session)
        try Self.validate(request.page)
        return try await image(encoded(request))
    }

    /// Covers use the selected HttpSource's headers and client. They are not
    /// page requests with invented context, and never use a Swift HTTP fallback.
    func coverData(session: MihonRuntimeSession, url: URL) async throws -> MihonRuntimeImagePayload {
        try Task.checkCancellation()
        try validate(session)
        try Self.validateKey(url.absoluteString)
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false else { throw MihonRuntimeError.invalidInput }
        return try await image(encoded(CoverRequest(session: session, url: url.absoluteString)))
    }

    private func image(_ input: String) async throws -> MihonRuntimeImagePayload {
        try Task.checkCancellation()
        let payload: MihonRuntimeImagePayload
        do { payload = try await imageBytes(input) }
        catch { try Task.checkCancellation(); throw error }
        try Task.checkCancellation()
        guard !payload.data.isEmpty else { throw MihonRuntimeError.invalidImage }
        guard payload.data.count <= Self.maximumImageBytes else { throw MihonRuntimeError.payloadTooLarge }
        if let count = payload.reportedByteCount, count != payload.data.count { throw MihonRuntimeError.invalidImage }
        if let hash = payload.reportedSHA256 {
            let actual = SHA256.hash(data: payload.data).map { String(format: "%02x", $0) }.joined()
            guard hash == actual else { throw MihonRuntimeError.invalidImage }
        }
        if let type = payload.mediaType {
            guard type.utf8.count <= 256, !Self.hasControl(type),
                  type.lowercased().hasPrefix("image/") || type.lowercased().split(separator: ";").first == "application/octet-stream" else {
                throw MihonRuntimeError.invalidImage
            }
        }
        try Task.checkCancellation()
        return payload
    }

    private func validate(_ session: MihonRuntimeSession) throws {
        try Self.validatePath(session.extensionPath)
        guard (try? MihonRepositoryCatalog.exactID(session.sourceId)) == session.sourceId,
              session.preferences.count <= 256,
              session.preferences.allSatisfy({ $0.key.utf8.count <= 1_024 && $0.value.utf8.count <= 16_384 }) else {
            throw MihonRuntimeError.invalidConfiguration
        }
        // Reject before allocating a large encoded request. JSON escaping can
        // still enlarge it, so the final encoded object has a second bound.
        var size = session.extensionPath.utf8.count + session.sourceId.utf8.count
        for (key, value) in session.preferences {
            size += key.utf8.count + value.utf8.count
            guard size <= Self.maximumRequestBytes else { throw MihonRuntimeError.payloadTooLarge }
        }
        if let packageIdentity, packageIdentity.extensionPath != session.extensionPath {
            throw MihonRuntimeError.identityMismatch
        }
    }

    private static func validatePath(_ path: String) throws {
        guard path.hasPrefix("/"), path.utf8.count <= 4_096, !hasControl(path),
              URL(fileURLWithPath: path).pathExtension.lowercased() == "jar" else {
            throw MihonRuntimeError.invalidConfiguration
        }
    }

    private static func validate(_ request: MihonRuntimeRequest) throws {
        switch request.operation {
        case .discover:
            guard request.query == nil, request.page == nil, request.manga == nil, request.chapter == nil else {
                throw MihonRuntimeError.invalidInput
            }
        case .search:
            guard let query = request.query, query.utf8.count <= 16_384,
                  let page = request.page, page > 0, page <= Int(Int32.max),
                  request.manga == nil, request.chapter == nil else { throw MihonRuntimeError.invalidInput }
        case .details, .chapters:
            guard request.query == nil, request.page == nil, request.chapter == nil,
                  let manga = request.manga, manga.title.utf8.count <= 16_384 else { throw MihonRuntimeError.invalidInput }
            try validateKey(manga.url)
            if let cover = manga.cover, !cover.isEmpty { try validateKey(cover) }
            for text in [manga.author, manga.artist, manga.description].compactMap({ $0 }) {
                guard text.utf8.count <= maximumRequestBytes else { throw MihonRuntimeError.payloadTooLarge }
            }
        case .pages:
            guard request.query == nil, request.page == nil, request.manga == nil,
                  let chapter = request.chapter, chapter.name.utf8.count <= 16_384,
                  chapter.number?.isFinite != false else { throw MihonRuntimeError.invalidInput }
            try validateKey(chapter.url)
            if let scanlator = chapter.scanlator, scanlator.utf8.count > maximumRequestBytes {
                throw MihonRuntimeError.payloadTooLarge
            }
        }
    }

    private static func validate(_ page: MihonRuntimePageRecord) throws {
        guard page.index >= 0, page.index <= Int(Int32.max),
              !page.url.isEmpty || page.imageUrl?.isEmpty == false else { throw MihonRuntimeError.invalidInput }
        if !page.url.isEmpty { try validateKey(page.url) }
        if let imageURL = page.imageUrl, !imageURL.isEmpty { try validateKey(imageURL) }
    }

    private static func validateKey(_ key: String) throws {
        guard !key.isEmpty, key.utf8.count <= 16_384, !hasControl(key), !key.contains("\\"),
              let url = URL(string: key), url.user == nil, url.password == nil else { throw MihonRuntimeError.invalidInput }
        if let scheme = url.scheme {
            guard ["https", "http"].contains(scheme.lowercased()), url.host?.isEmpty == false else {
                throw MihonRuntimeError.invalidInput
            }
        }
    }

    private static func hasControl(_ string: String) -> Bool {
        string.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }

    private func encoded<Request: Encodable>(_ request: Request) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do { data = try encoder.encode(BoundRequest(request: request, identity: packageIdentity)) }
        catch { throw MihonRuntimeError.invalidInput }
        guard data.count <= Self.maximumRequestBytes else { throw MihonRuntimeError.payloadTooLarge }
        let text = String(decoding: data, as: UTF8.self)
        guard text.utf16.count <= Self.maximumRequestUTF16Units else { throw MihonRuntimeError.payloadTooLarge }
        return text
    }

    private struct BoundRequest<Request: Encodable>: Encodable {
        let request: Request
        let identity: PackageIdentity?
        private enum CodingKeys: String, CodingKey { case packageSHA256, packageName, versionName, extensionLibrary }
        func encode(to encoder: Encoder) throws {
            try request.encode(to: encoder)
            guard let identity else { return }
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(identity.packageSHA256, forKey: .packageSHA256)
            try values.encode(identity.packageName, forKey: .packageName)
            try values.encode(identity.versionName, forKey: .versionName)
            try values.encode(identity.extensionLibrary, forKey: .extensionLibrary)
        }
    }

    private struct CoverRequest: Encodable {
        let session: MihonRuntimeSession
        let url: String
        private enum CodingKeys: String, CodingKey { case extensionPath, sourceId, preferences, operation, url }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(session.extensionPath, forKey: .extensionPath)
            try values.encode(session.sourceId, forKey: .sourceId)
            try values.encode(session.preferences, forKey: .preferences)
            try values.encode("cover", forKey: .operation)
            try values.encode(url, forKey: .url)
        }
    }
}
