#if SUMI
import Foundation
import StoreKit

enum HonbakoRemoteMCP {
    static let productionEndpoint = URL(string: "https://mcp.honbako.xyz/remote")!
    static let sandboxEndpoint = URL(string: "https://test-mcp.honbako.xyz/remote")!
    // Both branded domains passed strict public DNS, TLS and OAuth discovery checks.
    // Before purchase, show the stable production URL. Once paired, the
    // service keeps that exact endpoint; enrollment uses verified StoreKit proof.
    static let endpoint = productionEndpoint

    static func endpoint(forVerifiedEnvironment environment: AppStore.Environment) -> URL? {
        switch environment {
        case .production: productionEndpoint
        case .sandbox: sandboxEndpoint
        default: nil
        }
    }

    private enum ManagedEnvironment { case production, sandbox }

    private static func managedEnvironment(for endpoint: URL) -> ManagedEnvironment? {
        // Match complete addresses, rather than canonicalizing arbitrary input.
        // Queries, credentials, ports, and alternate paths must not acquire a
        // managed workspace identity merely because their host looks familiar.
        switch endpoint.absoluteString {
        case productionEndpoint.absoluteString, "https://honbako-mcp.jun-19c.workers.dev/remote": .production
        case sandboxEndpoint.absoluteString, "https://honbako-mcp-pro-preview.jun-19c.workers.dev/remote": .sandbox
        default: nil
        }
    }

    static func isManaged(_ endpoint: URL) -> Bool {
        managedEnvironment(for: endpoint) != nil
    }

    static func identityAccount(for endpoint: URL) -> String? {
        switch managedEnvironment(for: endpoint) {
        case .production: "remote-installation"
        case .sandbox: "remote-installation.sandbox"
        case nil: nil
        }
    }

    /// Used only when displaying setup addresses for a new AI connection.
    /// Saved phone endpoints, credentials, and existing OAuth issuers stay put.
    static func preferredAIConnectionEndpoint(for endpoint: URL) -> URL? {
        switch managedEnvironment(for: endpoint) {
        case .production: productionEndpoint
        case .sandbox: sandboxEndpoint
        case nil: nil
        }
    }

    struct Capabilities: Decodable { let available: Bool }

    struct Enrollment: Encodable {
        let installationId: String
        let deviceSecret: String
        let name: String
        let signedTransaction: String
    }
    struct Enrolled: Decodable {
        let deviceId: String
        let deviceToken: String
        let endpoint: URL
    }
    struct Authorization: Decodable, Identifiable, Sendable {
        let id: String
        let clientName: String
        let callbackHost: String
        let expiresAt: String
    }
    struct AuthorizationRequest: Encodable {
        let requestId: String
        var approved: Bool?
    }
    static func authorizationID(from url: URL) -> String? {
        guard url.scheme == "honbako", url.host == "mcp-authorize", url.path.isEmpty,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.fragment == nil,
              let items = components.queryItems, items.count == 1, items[0].name == "request",
              let value = items[0].value, let id = UUID(uuidString: value), id.uuidString.lowercased() == value else { return nil }
        return value
    }
}
#endif
