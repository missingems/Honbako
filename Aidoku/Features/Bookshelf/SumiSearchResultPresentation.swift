#if SUMI
import Foundation
import AidokuRunner

struct SumiSearchResultPresentation {
    enum Action: String {
        case get = "Add"
        case read = "Read"
        case resume = "Resume"
    }

    let action: Action
    let readingPosition: String?
    let publicationSubtitle: String?
    let compactPublicationSubtitle: String?
    let publicationBadge: String?

    init(book: SumiBook, isInLibrary: Bool, releaseYear: Int? = nil, isOngoing: Bool? = nil,
         publishingStatus: AidokuRunner.PublishingStatus? = nil) {
        let release = book.releaseDateLabel ?? releaseYear.flatMap { (1...9999).contains($0) ? "Released \($0)" : nil }
        let enriched = publishingStatus.flatMap { $0 == .unknown ? nil : $0 }
            ?? (isOngoing == true ? .ongoing : .unknown)
        let status = book.manga.status == .unknown ? enriched : book.manga.status
        switch status {
        case .ongoing: publicationBadge = "Ongoing"
        case .completed: publicationBadge = "Finished"
        default: publicationBadge = nil
        }
        publicationSubtitle = release
        let year = book.releaseDate?.formatted(.dateTime.year())
            ?? [book.releaseYear, releaseYear].compactMap { $0 }.first { (1...9999).contains($0) }.map(String.init)
        compactPublicationSubtitle = year
        let hasRead = book.lastRead != nil || book.bookmark != nil || (book.progress ?? 0) > 0
        action = hasRead ? .resume : (isInLibrary ? .read : .get)
        guard hasRead else { readingPosition = nil; return }
        let chapter = book.chapterLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let page = book.lastReadPage ?? book.bookmark?.page
        if let chapter, !chapter.isEmpty, let page, page > 0 {
            readingPosition = "\(chapter)-\(page)"
        } else if let page, page > 0 {
            readingPosition = "Page \(page)"
        } else {
            readingPosition = chapter?.isEmpty == false ? chapter : nil
        }
    }
}
#endif
