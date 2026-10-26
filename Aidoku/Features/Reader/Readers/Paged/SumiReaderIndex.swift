#if SUMI
import AidokuRunner
import Foundation

/// Front matter belongs to the book presentation, never its canonical pages or
/// persisted chapter positions. Only a first-read opening installs this value.
struct SumiReaderIndex {
    let manga: AidokuRunner.Manga
    let chapters: [SumiChapterSnapshot]
    let openingChapterKey: String

    init(manga: AidokuRunner.Manga, chapters: [SumiChapterSnapshot], openingChapterKey: String) {
        self.manga = manga
        self.chapters = chapters
        self.openingChapterKey = openingChapterKey
    }

    var readingOrder: [SumiChapterSnapshot] { chapters.reversed() }
    func applies(to chapter: AidokuRunner.Chapter?) -> Bool { chapter?.key == openingChapterKey }
}
#endif
