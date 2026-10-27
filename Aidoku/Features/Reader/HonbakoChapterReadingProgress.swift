#if SUMI
import Foundation

struct HonbakoChapterReadingProgress: Sendable, Equatable {
    var page: Int = 0
    var total: Int = 0
    var completed = false

    var label: String {
        if total > 0 {
            let visiblePage = completed ? total : min(total, max(1, page))
            return String(localized: "Pg \(visiblePage) of \(total)")
        }
        if completed { return String(localized: "Chapter Read", defaultValue: "Read") }
        if page > 0 { return String(localized: "Pg \(page)") }
        return String(localized: "Unread")
    }
}
#endif
