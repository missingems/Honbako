#if SUMI && HONBAKO_EXTERNAL_SOURCES
import AidokuRunner

/// Used only after a default edition has been confirmed unavailable. A saved
/// manual language choice is a lock; this policy never rewrites it or source
/// preferences. Each replacement chapter gets its own page-one position.
enum SumiAlternativeEditionOpening {
    struct Plan {
        let readableChapters: [AidokuRunner.Chapter]
        let choices: [SumiReaderOpeningPolicy.Choice]
    }

    static func mayRecover(explicitLanguage: String?, metadataFailed: Bool,
                           candidateStates: [HonbakoChapterAvailability.State]) -> Bool {
        !metadataFailed && SumiChapterLanguage.normalized(explicitLanguage) == nil
            && candidateStates.allSatisfy { $0 == .unavailable }
    }

    static func plan(original: [AidokuRunner.Chapter], alternativesNewestFirst: [AidokuRunner.Chapter],
                     history: SumiReaderHistorySnapshot?, explicitLanguage: String?,
                     configuredLanguages: [String], deviceLanguages: [String]) -> Plan? {
        guard SumiChapterLanguage.normalized(explicitLanguage) == nil else { return nil }
        let readable = alternativesNewestFirst.filter { !$0.locked }
        var seen: Set<String> = []
        let readingOrderLanguages = readable.reversed().compactMap { SumiChapterLanguage.normalized($0.language) }
            .filter { seen.insert($0).inserted }
        guard !readingOrderLanguages.isEmpty else { return nil }
        let available = Set(readingOrderLanguages)
        var languages: [String] = []
        for preference in configuredLanguages + deviceLanguages {
            guard let normalized = SumiChapterLanguage.normalized(preference) else { continue }
            for candidate in [normalized, normalized.split(separator: "-").first.map(String.init) ?? normalized]
                where available.contains(candidate) && !languages.contains(candidate) {
                languages.append(candidate)
            }
        }
        languages += readingOrderLanguages.filter { !languages.contains($0) }
        let originalChapter = history.flatMap { saved in original.first { $0.key == saved.chapterKey } }
        let choices = languages.flatMap { language -> [SumiReaderOpeningPolicy.Choice] in
            let edition = SumiChapterLanguage.filter(readable, language: language)
            var anchor = history
            if let history, !edition.contains(where: { $0.key == history.chapterKey }), let originalChapter,
               let equivalent = SumiChapterLanguage.equivalent(to: originalChapter, in: edition, language: language) {
                anchor = .init(chapterKey: equivalent.key, page: 1, completed: false)
            }
            return SumiReaderOpeningPolicy.candidates(history: anchor, chaptersNewestFirst: edition, canRead: { !$0.locked })
        }
        return Plan(readableChapters: readable, choices: choices)
    }
}
#endif
