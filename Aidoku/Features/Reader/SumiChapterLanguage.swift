#if SUMI
import AidokuRunner
import Foundation

enum SumiChapterLanguage {
    /// Preserve regional/script distinctions (pt-BR, zh-Hant) in reader routes.
    static func normalized(_ code: String?) -> String? {
        guard let code else { return nil }
        let result = code.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-").lowercased()
        if result.isEmpty || result == "multi" { return nil }
        // MangaFire returns es-la for the es-419 source preference. They name
        // the same regional edition; do not collapse it into Spanish (es).
        return result == "es-la" ? "es-419" : result
    }

    static func languages(in chapters: [AidokuRunner.Chapter]) -> [String] {
        Array(Set(chapters.compactMap { normalized($0.language) })).sorted {
            SourceLanguage.displayName(for: $0).localizedStandardCompare(SourceLanguage.displayName(for: $1)) == .orderedAscending
        }
    }

    static func activeLanguage(chapters: [AidokuRunner.Chapter], currentChapter: AidokuRunner.Chapter?, preferred: String?) -> String? {
        // Restoring the actual chapter wins over a choice made on another device.
        if let currentChapter { return normalized(currentChapter.language) }
        let available = languages(in: chapters)
        if let preferred = normalized(preferred), available.contains(preferred) { return preferred }
        for language in Locale.preferredLanguages {
            if let code = normalized(language), available.contains(code) { return code }
            if let base = normalized(language)?.split(separator: "-").first.map(String.init), available.contains(base) { return base }
        }
        return available.contains("en") ? "en" : available.first
    }

    static func filter(_ chapters: [AidokuRunner.Chapter], language: String?) -> [AidokuRunner.Chapter] {
        guard let language = normalized(language) else { return chapters }
        return chapters.filter { normalized($0.language) == language }
    }

    /// Match an edition of the same chapter, never a chapter's position in the
    /// source response. Specials and volume-based numbering can differ between
    /// translations, so an ambiguous match stays in the chapter picker.
    static func equivalent(to current: AidokuRunner.Chapter, in chapters: [AidokuRunner.Chapter],
                           language: String) -> AidokuRunner.Chapter? {
        guard let language = normalized(language) else { return nil }
        let translated = filter(chapters, language: language)
        if let exact = translated.first(where: { $0.key == current.key }) { return exact }
        let candidates: [AidokuRunner.Chapter]
        if let number = current.chapterNumber {
            candidates = translated.filter { $0.chapterNumber == number }
        } else if let title = matchingTitle(current.title) {
            candidates = translated.filter { $0.chapterNumber == nil && matchingTitle($0.title) == title }
        } else {
            return nil
        }
        if let volume = current.volumeNumber {
            if let exactVolume = candidates.first(where: { $0.volumeNumber == volume }) { return exactVolume }
            // Some translations omit volume metadata entirely. A response with
            // another explicit volume is insufficient evidence of equivalence.
            return candidates.allSatisfy { $0.volumeNumber == nil } ? candidates.first : nil
        }
        if let unnumberedVolume = candidates.first(where: { $0.volumeNumber == nil }) { return unnumberedVolume }
        return Set(candidates.compactMap(\.volumeNumber)).count <= 1 ? candidates.first : nil
    }

    /// A translation's own bookmark wins. Otherwise keep the visible canonical
    /// page; the reader clamps it to the translated chapter's real page count.
    static func resumePage(savedPage: Int?, currentPage: Int) -> Int {
        if let savedPage, savedPage > 0 { return savedPage }
        return max(1, currentPage)
    }

    private static func matchingTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let result = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return result.isEmpty ? nil : result
    }

    static func merge(_ existing: [AidokuRunner.Chapter], with fetched: [AidokuRunner.Chapter]) -> [AidokuRunner.Chapter] {
        var seen: Set<String> = []
        // Preserve each response's source order, including specials and volume
        // resets. Sorting translations together by chapter number can reorder
        // an otherwise correct route within one language.
        return (fetched + existing).filter { seen.insert($0.key).inserted }
    }

    /// A provider may return only its globally selected language. That response
    /// is authoritative for the languages it contains, not other translations
    /// explicitly loaded by this reader and synced from another device.
    static func retainingOtherLanguages(existing: [AidokuRunner.Chapter], fetched: [AidokuRunner.Chapter]) -> [AidokuRunner.Chapter] {
        let represented = Set(fetched.compactMap { normalized($0.language) })
        let retained = existing.filter { chapter in
            guard let language = normalized(chapter.language) else { return false }
            return !represented.contains(language)
        }
        return merge(retained, with: fetched)
    }

    @MainActor
    static func persistedLanguage(mangaID: MangaIdentifier) -> String? {
        CoreDataManager.shared.getMangaChapterFilters(mangaId: mangaID, context: CoreDataManager.shared.context).language
    }

    static func persist(language: String?, chapters: [AidokuRunner.Chapter], manga: AidokuRunner.Manga) async throws {
        guard !AppSettings.general.incognitoMode.get() else { return }
        try await CoreDataManager.shared.container.performBackgroundTask { context in
            let manager = CoreDataManager.shared
            let object = manager.getOrCreateManga(manga, context: context)
            object.langFilter = normalized(language)
            // Preserve translations and their bookmarks when another language is fetched.
            let stored = manager.getChapters(mangaId: manga.identifier, context: context).map { $0.toNewChapter() }
            manager.setChapters(merge(stored, with: chapters), mangaId: manga.identifier, context: context)
            try context.save()
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .filteredChapters, object: manga.identifier)
        }
    }
}
#endif
