import Foundation

/// Repository metadata only. Parsing a package does not install it, verify its
/// signing key, or establish that Honbako can execute its extension API.
struct MihonRepositoryCatalog: Equatable, Sendable {
    enum Format: Equatable, Sendable { case legacyJSON, json, protobuf }

    struct Contact: Equatable, Sendable {
        let website: URL?
        let discord: URL?
    }

    struct Metadata: Equatable, Sendable {
        let name: String
        let badgeLabel: String
        /// An unverified claim from the repository, not a trusted key.
        let signingKey: String
        let contact: Contact
    }

    struct Artifact: Equatable, Sendable {
        enum Format: Equatable, Sendable { case androidAPK, javaArchive }
        let format: Format
        let url: URL
    }

    struct Source: Equatable, Sendable {
        /// Exact signed-int64 decimal representation. Never converted to Double.
        let id: String
        let name: String
        let language: String
        let homeURL: URL?
        let mirrorURLs: [URL]
        let message: String?
        /// Present only in some legacy JSON repositories.
        let versionID: Int64?
    }

    struct Package: Equatable, Sendable {
        let name: String
        let packageName: String
        let extensionLib: String
        let versionCode: Int64
        let versionName: String
        let language: String
        /// Proto content-warning value; unknown values remain unknown.
        let contentWarning: Int64
        let iconURL: URL?
        let artifacts: [Artifact]
        /// Empty means the catalog does not enumerate its sources. No fake ID
        /// is synthesized; runtime inspection must discover the real sources.
        let sources: [Source]
    }

    let indexURL: URL
    let format: Format
    /// Legacy index.min.json has no repository identity/signing metadata.
    let metadata: Metadata?
    let packages: [Package]
    /// Follow-up resource only. This parser performs no network requests.
    let extensionListURL: URL?

    enum ParseError: Error, Equatable {
        case payloadTooLarge
        case malformedJSON
        case malformedProtobuf
        case malformedGzip
        case invalidField(String)
        case invalidURL(String)
        case duplicatePackage(String)
        case duplicateSource(String)
    }

    static let maximumPayloadBytes = 16 * 1024 * 1024
    static let maximumPackages = 20_000

    static func parse(_ data: Data, indexURL: URL) throws -> Self {
        try validateIndexURL(indexURL)
        let payload = try MihonCatalogPayload.uncompressed(data)
        switch payload.firstNonWhitespaceByte {
            case 0x5B, 0x7B:
                do { return try MihonJSONCatalog.parse(payload, indexURL: indexURL) }
                catch {
                    // Protobuf's name-field tag is 0x0A, also a JSON newline.
                    // A valid binary name can follow it with '[' or '{'.
                    if let binary = try? MihonProtobufCatalog.parse(payload, indexURL: indexURL) { return binary }
                    throw error
                }
            case nil: throw ParseError.invalidField("empty catalog")
            default: return try MihonProtobufCatalog.parse(payload, indexURL: indexURL)
        }
    }

    /// Decodes the separate ExtensionList referenced by a modern index. Relative
    /// resource URLs use this list's own URL, rather than the first index URL.
    static func parseExtensionList(_ data: Data, listURL: URL) throws -> [Package] {
        try validateIndexURL(listURL)
        let payload = try MihonCatalogPayload.uncompressed(data)
        let packages: [Package]
        if payload.firstNonWhitespaceByte == 0x7B {
            do { packages = try MihonJSONCatalog.parseExtensionList(payload, url: listURL) }
            catch {
                if let binary = try? MihonProtobufCatalog.parseExtensionList(payload, url: listURL) { packages = binary }
                else { throw error }
            }
        } else {
            packages = try MihonProtobufCatalog.parseExtensionList(payload, url: listURL)
        }
        try validate(packages)
        return packages
    }

    static func validate(_ packages: [Package]) throws {
        guard packages.count <= maximumPackages else { throw ParseError.payloadTooLarge }
        var names: Set<String> = []
        for package in packages {
            guard names.insert(package.packageName).inserted else { throw ParseError.duplicatePackage(package.packageName) }
            guard !package.name.isEmpty, validPackageName(package.packageName),
                  !package.versionName.isEmpty, package.versionCode > 0,
                  validLibraryVersion(package.extensionLib), !package.artifacts.isEmpty,
                  package.sources.count <= 10_000 else { throw ParseError.invalidField("extension") }
            var sources: Set<String> = []
            for source in package.sources {
                guard !source.name.isEmpty, !source.language.isEmpty else { throw ParseError.invalidField("source") }
                guard sources.insert(source.id).inserted else { throw ParseError.duplicateSource(source.id) }
            }
        }
    }

    static func resolvedURL(_ value: String?, relativeTo base: URL, metadata: Bool = false) throws -> URL? {
        guard let value, !value.isEmpty else { return nil }
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.contains("\\"), !value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
              let url = URL(string: value, relativeTo: base)?.absoluteURL,
              url.user == nil, url.password == nil, metadata || url.fragment == nil,
              let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty,
              scheme == "https" || (scheme == "http" && (metadata || isLoopback(host))) else {
            throw ParseError.invalidURL(value)
        }
        return url
    }

    static func validateIndexURL(_ url: URL) throws {
        guard try resolvedURL(url.absoluteString, relativeTo: url) != nil else {
            throw ParseError.invalidURL(url.absoluteString)
        }
    }

    static func requiredURL(_ value: String, relativeTo base: URL, metadata: Bool = false) throws -> URL {
        guard let url = try resolvedURL(value, relativeTo: base, metadata: metadata) else { throw ParseError.invalidURL(value) }
        return url
    }

    static func exactID(_ value: String) throws -> String {
        guard let number = Int64(value), value == String(number) else { throw ParseError.invalidField("source id") }
        return String(number)
    }

    private static func isLoopback(_ host: String) -> Bool {
        let host = host.lowercased()
        if ["localhost", "::1", "[::1]"].contains(host) { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.first == "127" && parts.allSatisfy { UInt8($0) != nil }
    }

    private static func validPackageName(_ value: String) -> Bool {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        return value.utf8.count <= 512 && components.count >= 2 && components.allSatisfy { part in
            guard let first = part.utf8.first, (65...90).contains(first) || (97...122).contains(first) || first == 95 else { return false }
            return part.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
        }
    }

    private static func validLibraryVersion(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }
    }
}

private extension Data {
    var firstNonWhitespaceByte: UInt8? {
        let bytes = starts(with: [0xEF, 0xBB, 0xBF]) ? dropFirst(3) : self[...]
        return bytes.first { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }
    }
}
