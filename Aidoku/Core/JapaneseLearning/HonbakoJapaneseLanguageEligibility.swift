#if SUMI
import Foundation

/// Reading-language metadata, not shared Han characters or the title's country of origin,
/// decides whether a page may enter the Japanese recognizer.
enum HonbakoJapaneseLanguageEligibility {
    static func allows(chapterLanguage: String?, sourceLanguages: [String]) -> Bool {
        if let chapterLanguage, !chapterLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // An explicit translation always wins, including unknown/multilingual labels.
            return isJapanese(chapterLanguage)
        }
        return !sourceLanguages.isEmpty && sourceLanguages.allSatisfy(isJapanese)
    }

    static func allowsPage(chapterLanguage: String?, sourceLanguages: [String], sourceKey: String,
                           mangaKey: String, chapterKey: String, pageIndex: Int) -> Bool {
        allows(chapterLanguage: chapterLanguage, sourceLanguages: sourceLanguages)
            || isOriginalPracticePage(sourceKey: sourceKey, mangaKey: mangaKey,
                                      chapterKey: chapterKey, pageIndex: pageIndex)
    }

    /// The original Japanese practice bitmap is page 2 in every localized edition
    /// of this one bundled guide. The surrounding English/Chinese guide stays gated.
    static func isOriginalPracticePage(sourceKey: String, mangaKey: String, chapterKey: String, pageIndex: Int) -> Bool {
        pageIndex == 1 && containsOriginalPracticePage(sourceKey: sourceKey, mangaKey: mangaKey, chapterKey: chapterKey)
    }

    static func containsOriginalPracticePage(sourceKey: String, mangaKey: String, chapterKey: String) -> Bool {
        guard sourceKey == HonbakoTutorialManga.sourceKey, mangaKey == HonbakoGuideBook.japanese.rawValue else { return false }
        return HonbakoTutorialManga.languages.contains { chapterKey == "\($0)-\(mangaKey)" }
    }

    private static func isJapanese(_ value: String) -> Bool {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-").lowercased()
        let parts = code.split(separator: "-", omittingEmptySubsequences: false)
        guard let first = parts.first, first == "ja" || first == "jpn" else { return false }
        return parts.allSatisfy { part in
            (1...8).contains(part.count) && part.utf8.allSatisfy {
                (97...122).contains($0) || (48...57).contains($0)
            }
        }
    }
}
#endif
