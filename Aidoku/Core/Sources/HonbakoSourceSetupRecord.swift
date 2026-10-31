#if SUMI
import Foundation

/// Explicit metadata only. Source preferences, cookies, passwords and tokens have no fields here.
struct HonbakoSourceSetupRecord: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case repository, local, komga, kavita, suwayomi, mangaDex, extensionPackage
    }

    var schemaVersion = 1
    let id: String
    let kind: Kind
    var name: String
    var version: Int?
    var serverURL: String?
    var repositoryURL: String?
    var packageURL: String?
    var packageSHA256: String?
    var disabled = false
    var removed = false
    var updatedAt = Date.now
}
#endif
