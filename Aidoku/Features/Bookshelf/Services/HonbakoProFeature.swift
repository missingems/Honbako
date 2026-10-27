#if SUMI
import Foundation

enum HonbakoProFeature: String, Identifiable {
    case offline, chapterAlerts, cloudProgress
    var id: String { rawValue }
    var title: String {
        switch self {
        case .offline: String(localized: "Offline Reading")
        case .chapterAlerts: String(localized: "Chapter Notifications")
        case .cloudProgress: String(localized: "iCloud Progress Sync")
        }
    }
}
#endif
