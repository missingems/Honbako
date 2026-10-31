#if SUMI
import Foundation

enum HonbakoMCPAuthorizationError: LocalizedError, Equatable {
    case inactive, connectionRequired, proRequired, requestExpired, unavailable, invalidResponse

    static func response(status: Int) -> Self {
        switch status {
        case 400, 410: .requestExpired
        case 401, 403: .connectionRequired
        case 402: .proRequired
        default: .unavailable
        }
    }

    var errorDescription: String? {
        switch self {
        case .inactive:
            "Keep Honbako open, then try again to check this connection request."
        case .connectionRequired:
            "Enable your remote MCP server in Settings, then try this request again. If it is already enabled, reconnect it first."
        case .proRequired:
            "Apple could not confirm an active Pro subscription. Restore Purchases in Settings, then try this request again."
        case .requestExpired:
            "This connection request has expired or has already been answered. Start a new connection from your AI."
        case .unavailable:
            "Couldn’t reach your remote server. Check your internet connection, then try again."
        case .invalidResponse:
            "The server returned an invalid connection request. Start a new connection from your AI."
        }
    }

    var canRetry: Bool { self != .requestExpired && self != .invalidResponse }
}
#endif
