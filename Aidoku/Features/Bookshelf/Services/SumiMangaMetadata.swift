#if SUMI
import AidokuRunner

enum SumiMangaMetadata {
    static func merging(_ original: AidokuRunner.Manga, with fetched: AidokuRunner.Manga) -> AidokuRunner.Manga {
        var result = original.copy(from: fetched)
        if fetched.viewer == .unknown { result.viewer = original.viewer }
        if let chapters = fetched.chapters {
            result.chapters = SumiChapterLanguage.retainingOtherLanguages(existing: original.chapters ?? [], fetched: chapters)
        }
        return result
    }
}
#endif
