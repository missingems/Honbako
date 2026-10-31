#if SUMI
import Foundation

enum HonbakoProFeature: String, Identifiable {
    case offline, chapterAlerts, cloudProgress, remoteMCP, coverDisplay, japaneseGuide, widgets
    var id: String { rawValue }
    var title: String {
        switch self {
        case .widgets: String(localized: "All Widgets")
        case .offline: String(localized: "Offline Reading")
        case .chapterAlerts: String(localized: "Chapter Notifications")
        case .coverDisplay: String(localized: "Duo Cover Display")
        case .japaneseGuide: String(localized: "Japanese Reading Guide")
        case .remoteMCP: String(localized: "Remote MCP Server")
        case .cloudProgress: String(localized: "iCloud Progress Sync")
        }
    }
}
#endif
