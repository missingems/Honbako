#if SUMI
import AidokuRunner
import Foundation

/// Supplied by the visible reader, never by a library or prefetch operation.
@MainActor
struct HonbakoPageCoachingCapture {
    let page: Page
    let source: AidokuRunner.Source?
    let sourceId: String
    let mangaId: String
    let title: String
    let chapterId: String
    let chapterTitle: String
    let chapterNumber: Double?
    let canonicalPage: Int
    let totalPages: Int?
    let lastVisiblePage: Int?
}
#endif
