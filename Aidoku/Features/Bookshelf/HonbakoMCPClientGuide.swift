#if SUMI
import Foundation

enum HonbakoMCPClientGuide: String, CaseIterable, Identifiable {
    case grok, chatgpt, claude
    var id: String { rawValue }
    var title: String {
        switch self {
        case .grok: "Grok / Grok Bot"
        case .chatgpt: "ChatGPT"
        case .claude: "Claude"
        }
    }

    static func remoteMCPURL(companionEndpoint: String) -> URL? {
        guard let endpoint = HonbakoAutomationPolicy.endpoint(companionEndpoint), endpoint.scheme == "https",
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "http"
        // The phone may pair over its LAN; a cloud assistant cannot use that URL.
        guard components.url.map({ HonbakoAutomationPolicy.endpoint($0.absoluteString) == nil }) == true else { return nil }
        return endpoint.appendingPathComponent("mcp")
    }
}
#endif
