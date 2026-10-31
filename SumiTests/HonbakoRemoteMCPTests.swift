@testable import Sumi
import Foundation
import StoreKit
import Testing

struct HonbakoRemoteMCPTests {
    @Test("An AI approval link carries only a request ID and cannot replace the server or auto-approve")
    func authorizationLinks() throws {
        let id = UUID().uuidString.lowercased()
        #expect(HonbakoRemoteMCP.authorizationID(from: try #require(URL(string: "honbako://mcp-authorize?request=\(id)"))) == id)
        for text in ["honbako://mcp-authorize?request=\(id)&approved=true", "honbako://mcp-authorize?request=\(id)&request=\(id)", "honbako://mcp-authorize?request=\(id)#secret", "honbako://mcp-authorize/other?request=\(id)", "https://mcp-authorize?request=\(id)", "honbako://mcp-authorize?endpoint=https://evil.example", "honbako://mcp-authorize?request=invalid"] {
            #expect(HonbakoRemoteMCP.authorizationID(from: try #require(URL(string: text))) == nil)
        }
    }
    @Test("Automatic setup distinguishes the managed service from arbitrary or legacy endpoints")
    func managedEndpoint() throws {
        #expect(HonbakoRemoteMCP.isManaged(HonbakoRemoteMCP.endpoint))
        #expect(!HonbakoRemoteMCP.isManaged(try #require(URL(string: "https://honbako-mcp.jun-19c.workers.dev"))))
        #expect(!HonbakoRemoteMCP.isManaged(try #require(URL(string: "https://evil.example/remote"))))
        #expect(!HonbakoRemoteMCP.isManaged(try #require(URL(string: "http://127.0.0.1:43187"))))
    }
    @Test("Both branded and original addresses retain the same environment-specific installation identity")
    func managedAliases() throws {
        for (address, account, preferred) in [
            ("https://mcp.honbako.xyz/remote", "remote-installation", HonbakoRemoteMCP.productionEndpoint),
            ("https://honbako-mcp.jun-19c.workers.dev/remote", "remote-installation", HonbakoRemoteMCP.productionEndpoint),
            ("https://test-mcp.honbako.xyz/remote", "remote-installation.sandbox", HonbakoRemoteMCP.sandboxEndpoint),
            ("https://honbako-mcp-pro-preview.jun-19c.workers.dev/remote", "remote-installation.sandbox", HonbakoRemoteMCP.sandboxEndpoint)
        ] {
            let endpoint = try #require(URL(string: address))
            #expect(HonbakoRemoteMCP.isManaged(endpoint))
            #expect(HonbakoRemoteMCP.identityAccount(for: endpoint) == account)
            #expect(HonbakoRemoteMCP.preferredAIConnectionEndpoint(for: endpoint) == preferred)
            let saved = HonbakoAutomationModels.Connection(endpoint: endpoint, deviceId: "existing-device", deviceToken: "existing-private-token")
            let restored = try JSONDecoder().decode(HonbakoAutomationModels.Connection.self, from: JSONEncoder().encode(saved))
            #expect(restored.endpoint.absoluteString == address, "Displaying a new AI address must not migrate the saved phone connection")
            #expect(restored.deviceId == saved.deviceId)
            #expect(restored.deviceToken == saved.deviceToken)
        }
    }

    @Test("Unknown hosts and modified managed addresses never acquire a managed identity or preferred alias")
    func modifiedAliasesAreRejected() throws {
        for address in [
            "https://evil.example/remote", "http://mcp.honbako.xyz/remote",
            "https://mcp.honbako.xyz", "https://mcp.honbako.xyz/remote/",
            "https://mcp.honbako.xyz/remote/mcp", "https://mcp.honbako.xyz/rem%6fte",
            "https://mcp.honbako.xyz/remote?key=value", "https://mcp.honbako.xyz/remote?",
            "https://mcp.honbako.xyz/remote#fragment", "https://user@mcp.honbako.xyz/remote",
            "https://mcp.honbako.xyz:443/remote", "https://test-mcp.honbako.xyz:8443/remote",
            "https://mcp.honbako.xyz.evil.example/remote",
            "https://honbako-mcp.jun-19c.workers.dev/remote?key=value",
            "https://honbako-mcp-pro-preview.jun-19c.workers.dev/remote/"
        ] {
            let endpoint = try #require(URL(string: address))
            #expect(!HonbakoRemoteMCP.isManaged(endpoint))
            #expect(HonbakoRemoteMCP.identityAccount(for: endpoint) == nil)
            #expect(HonbakoRemoteMCP.preferredAIConnectionEndpoint(for: endpoint) == nil)
        }
    }

    @Test("Verified Apple environments route hosting without build flags or namespace mixing")
    func verifiedEnvironmentRouting() {
        let production = HonbakoRemoteMCP.productionEndpoint
        let sandbox = HonbakoRemoteMCP.sandboxEndpoint
        #expect(production.absoluteString == "https://mcp.honbako.xyz/remote")
        #expect(sandbox.absoluteString == "https://test-mcp.honbako.xyz/remote")
        #expect(HonbakoRemoteMCP.endpoint == production)
        #expect(HonbakoRemoteMCP.endpoint(forVerifiedEnvironment: .production) == production)
        #expect(HonbakoRemoteMCP.endpoint(forVerifiedEnvironment: .sandbox) == sandbox)
        #expect(HonbakoRemoteMCP.endpoint(forVerifiedEnvironment: .xcode) == nil)
        #expect(HonbakoRemoteMCP.endpoint(forVerifiedEnvironment: .init(rawValue: "Unknown")) == nil)
        #expect(HonbakoRemoteMCP.isManaged(production))
        #expect(HonbakoRemoteMCP.isManaged(sandbox))
        #expect(HonbakoRemoteMCP.identityAccount(for: production) == "remote-installation")
        #expect(HonbakoRemoteMCP.identityAccount(for: sandbox) == "remote-installation.sandbox")
    }

}
