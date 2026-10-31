#if SUMI
import CryptoKit
import Foundation

/// Bounded, credential-free records fit within iCloud key-value storage without a model migration.
enum HonbakoSourceSetupPolicy {
    static let prefix = "Honbako.SourceSetup.v1."
    static let maxRecordBytes = 8_192
    static let maxRecords = 384
    static let maxTotalBytes = 512_000

    static func sourceID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_ ").subtracting(.whitespaces)).contains($0)
        }
    }

    static func safeURL(_ value: String, personalServer: Bool = false) -> URL? {
        guard value.utf8.count <= 2_048, !value.contains(where: { $0.isWhitespace || $0.isNewline }),
              let url = URL(string: value), url.host?.isEmpty == false,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.scheme == "https" || (personalServer && url.scheme == "http") else { return nil }
        return url
    }

    static func validate(_ record: HonbakoSourceSetupRecord) -> Bool {
        guard record.schemaVersion == 1, !record.name.isEmpty, record.name.utf8.count <= 500,
              record.updatedAt.timeIntervalSince1970.isFinite else { return false }
        if record.kind == .repository {
            guard safeURL(record.id) != nil, record.repositoryURL == record.id,
                  record.serverURL == nil, record.packageURL == nil, record.packageSHA256 == nil else { return false }
        } else {
            guard sourceID(record.id) else { return false }
        }
        if let version = record.version, !(0...1_000_000).contains(version) { return false }
        if let value = record.repositoryURL, safeURL(value) == nil { return false }
        if let value = record.packageURL, safeURL(value) == nil { return false }
        if let hash = record.packageSHA256,
           hash.count != 64 || !hash.allSatisfy({ "0123456789abcdef".contains($0) }) { return false }
        switch record.kind {
        case .komga, .kavita, .suwayomi:
            guard record.id.hasPrefix(record.kind.rawValue + ".") else { return false }
            guard let value = record.serverURL, safeURL(value, personalServer: true) != nil,
                  record.packageURL == nil, record.packageSHA256 == nil else { return false }
        case .extensionPackage:
            guard record.serverURL == nil, !["local", "komga", "kavita", "suwayomi", "honbako."].contains(where: { record.id.hasPrefix($0) }) else { return false }
        case .local, .mangaDex, .repository:
            if record.kind == .local && record.id != "local" { return false }
            if record.kind == .mangaDex && record.id != "honbako.mangadex" { return false }
            guard record.serverURL == nil, record.packageURL == nil, record.packageSHA256 == nil else { return false }
        }
        return true
    }

    static func key(for record: HonbakoSourceSetupRecord) -> String {
        let group = record.kind == .repository ? "repository." : "source."
        return prefix + group + SHA256.hash(data: Data(record.id.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func encode(_ record: HonbakoSourceSetupRecord) -> Data? {
        guard validate(record), let data = try? JSONEncoder().encode(record), data.count <= maxRecordBytes else { return nil }
        return data
    }

    static func decode(_ data: Data, key: String) -> HonbakoSourceSetupRecord? {
        guard data.count <= maxRecordBytes, let value = try? JSONDecoder().decode(HonbakoSourceSetupRecord.self, from: data),
              validate(value), self.key(for: value) == key else { return nil }
        return value
    }

    static func sameSetup(_ lhs: HonbakoSourceSetupRecord, _ rhs: HonbakoSourceSetupRecord) -> Bool {
        var left = lhs, right = rhs
        left.updatedAt = .distantPast
        right.updatedAt = .distantPast
        return left == right
    }

    /// Never initialize a real iCloud writer for unit/UI tests or launch fixtures.
    static func permitsLiveStore(arguments: [String], environment: [String: String]) -> Bool {
        guard environment["XCTestConfigurationFilePath"] == nil, environment["XCTestBundlePath"] == nil,
              environment["XCTestSessionIdentifier"] == nil else { return false }
        return !arguments.contains {
            let flag = $0.lowercased()
            return flag.hasPrefix("--sumi-") || flag.hasPrefix("--honbako-")
                || flag.hasPrefix("-sumi-") || flag.hasPrefix("-honbako-")
                || flag.contains("screenshot") || flag.contains("fixture") || flag.contains("uitest")
        }
    }

    static func matchesPackage(id: String, version: Int?, digest: String?, expectedID: String?, expectedVersion: Int?, expectedDigest: String?) -> Bool {
        (expectedID == nil || id == expectedID)
            && (expectedVersion == nil || version == expectedVersion)
            && (expectedDigest == nil || digest == expectedDigest)
    }

    static func packageDigest(at url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let bytes = try file.read(upToCount: 1_048_576), !bytes.isEmpty { hash.update(data: bytes) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
#endif
