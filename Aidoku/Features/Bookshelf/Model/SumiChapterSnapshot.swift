#if SUMI
import AidokuRunner
import Foundation

/// Chapter metadata and reading state copied out of the database context.
struct SumiChapterSnapshot: Identifiable, Hashable, Sendable {
    let id: ChapterIdentifier
    let chapter: AidokuRunner.Chapter
    let completed: Bool
    let currentPage: Int?
    let totalPages: Int?
    let isCurrent: Bool
    let canRead: Bool

    var title: String {
        if let number = chapter.chapterNumber {
            return "Chapter \(String(format: "%g", Double(number)))"
        }
        if let title = chapter.title, !title.isEmpty { return title }
        if let number = chapter.volumeNumber {
            return "Volume \(String(format: "%g", Double(number)))"
        }
        return "Chapter"
    }

    var subtitle: String? {
        let title = chapter.title.flatMap { $0.isEmpty || $0 == self.title ? nil : $0 }
        let groups = chapter.scanlators?.filter { !$0.isEmpty }.joined(separator: ", ")
        let parts = [title, groups].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var progressLabel: String {
        if completed { return "Read" }
        if let currentPage, currentPage > 0 {
            if let totalPages, totalPages > 0 {
                return "Page \(currentPage) of \(totalPages)"
            }
            return "Page \(currentPage)"
        }
        return isCurrent ? "Next to read" : "Unread"
    }

    var progressFraction: Double? {
        guard !completed, let currentPage, let totalPages,
              currentPage > 0, totalPages > 0 else { return nil }
        return min(1, max(0, Double(currentPage) / Double(totalPages)))
    }
}
#endif
