@testable import Sumi
import Foundation
import Testing

struct HonbakoMCPClientGuideTests {
    @Test("AI setup derives only a credential-free remote HTTPS MCP endpoint")
    func publicEndpoint() {
        #expect(HonbakoMCPClientGuide.remoteMCPURL(companionEndpoint: "https://reader.workers.dev")?.absoluteString == "https://reader.workers.dev/mcp")
        #expect(HonbakoMCPClientGuide.remoteMCPURL(companionEndpoint: "https://reader.example/bridge/")?.absoluteString == "https://reader.example/bridge/mcp")
        for endpoint in ["", "http://127.0.0.1:43187", "https://localhost", "https://192.168.1.3", "https://reader.local", "https://[::1]", "https://user:secret@reader.example", "https://reader.example?key=secret", "https://reader.example#secret"] {
            #expect(HonbakoMCPClientGuide.remoteMCPURL(companionEndpoint: endpoint) == nil)
        }
    }
}
