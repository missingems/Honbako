#if SUMI
import AidokuRunner

struct HonbakoMangaDexSearchPreparation: Sendable {
    /// Details are complete enough for a search row, but chapters stay nil:
    /// the separate one-chapter probe is not a complete chapter collection.
    let manga: AidokuRunner.Manga
    let readableChapter: AidokuRunner.Chapter?
    let translatedLanguages: [String]
    let releaseYear: Int?
}
#endif
