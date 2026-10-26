#if SUMI
import Foundation

enum HonbakoProFeature: String, Identifiable {
    case offline, chapterAlerts, cloudProgress
    var id: String { rawValue }
    var title: String {
        switch self {
        case .offline: "Offline Reading"
        case .chapterAlerts: "Chapter Notifications"
        case .cloudProgress: "iCloud Progress Sync"
        }
    }
}
#endif
