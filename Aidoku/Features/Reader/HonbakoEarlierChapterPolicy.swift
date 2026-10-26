#if SUMI
import AidokuRunner
import Foundation

enum HonbakoEarlierChapterPolicy {
    /// Providers retain their own sequence for specials and volume resets.
    /// Aidoku chapter arrays arrive newest first; reverse only the chosen translation.
    static func unreadBefore(_ selected: AidokuRunner.Chapter, in chapters: [AidokuRunner.Chapter],
                             completedKeys: Set<String>) -> [AidokuRunner.Chapter] {
        let language = SumiChapterLanguage.normalized(selected.language)
        let matching = language == nil ? chapters.filter { SumiChapterLanguage.normalized($0.language) == nil }
            : SumiChapterLanguage.filter(chapters, language: language)
        let ascending = Array(matching.reversed())
        guard let index = ascending.firstIndex(where: { $0.key == selected.key }) else { return [] }
        var seen: Set<String> = []
        return ascending[..<index].filter { !completedKeys.contains($0.key) && seen.insert($0.key).inserted }
    }
}
#endif
