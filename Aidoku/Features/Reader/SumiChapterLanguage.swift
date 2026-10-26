#if SUMI
import AidokuRunner
import Foundation

enum SumiChapterLanguage {
    /// Preserve regional/script distinctions (pt-BR, zh-Hant) in reader routes.
    static func normalized(_ code: String?) -> String? {
        guard let code else { return nil }
        let result = code.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-").lowercased()
        return result.isEmpty || result == "multi" ? nil : result
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
