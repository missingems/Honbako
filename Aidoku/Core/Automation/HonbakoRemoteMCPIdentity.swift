#if SUMI
import Foundation
import Security

struct HonbakoRemoteMCPIdentity: Codable, Sendable {
    let installationId: String
    let deviceSecret: String

    static func create() throws -> Self {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CocoaError(.fileReadUnknown)
        }
        let secret = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return .init(installationId: UUID().uuidString.lowercased(), deviceSecret: secret)
    }
}
#endif
