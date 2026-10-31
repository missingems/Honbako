#if SUMI
import AidokuRunner

/// A library-change snapshot. Scroll/reveal updates read these arrays without
/// filtering and sorting the whole collection again.
struct SumiLibraryShelves: Equatable {
    let reading: [SumiBook]
    let finished: [SumiBook]

    init(books: [SumiBook] = [], stableIDs: [String] = [], tutorialIdentifier: MangaIdentifier? = nil) {
        reading = SumiLibraryShelfSummary.readingOrder(books, stableIDs: stableIDs,
            tutorialIdentifier: tutorialIdentifier)
        finished = SumiLibraryShelfSummary.finishedOrder(books, hidden: false)
    }

    func visibleCount(hideFinished: Bool) -> Int {
        reading.count + (hideFinished ? 0 : finished.count)
    }
}
#endif
