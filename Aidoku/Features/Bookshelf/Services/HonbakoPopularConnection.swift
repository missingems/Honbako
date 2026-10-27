#if SUMI
import AidokuRunner
import CryptoKit
import Foundation

/// A connection snapshot makes cache membership explicit. It never installs a
/// source or changes the reader's source preferences.
struct HonbakoPopularConnection: Sendable {
    struct Identity: Hashable, Codable, Sendable {
        let sourceKey: String
        let revision: String
    }

    let id: Identity
    let name: String
    let load: @Sendable () async throws -> [AidokuRunner.Manga]

    init(key: String, revision: String = "1", name: String? = nil,
         load: @escaping @Sendable () async throws -> [AidokuRunner.Manga]) {
        id = Identity(sourceKey: key, revision: revision)
        self.name = name ?? key
        self.load = load
    }

    init(source: AidokuRunner.Source) {
        self.init(key: source.key, revision: Self.revision(for: source), name: source.name) {
            try await HonbakoPopularLoader.load(source: source)
        }
    }

    private static func revision(for source: AidokuRunner.Source) -> String {
        let defaults = UserDefaults.standard.dictionaryRepresentation()
            .filter { $0.key.hasPrefix(source.key + ".") }
        let preferences: [[Any]] = defaults.keys.sorted().map { [$0, defaults[$0]!] }
        let inputs: [Any] = [source.version, source.urls.map(\.absoluteString), source.languages, preferences]
        let data = (try? PropertyListSerialization.data(fromPropertyList: inputs, format: .binary, options: 0)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
