#if SUMI
import AidokuRunner
import Foundation

/// A temporary interpreter has its own defaults namespace. Fetching one
/// translation cannot change another reader, background update, or search.
enum SumiLanguageChapterLoader {
    static func update(source: AidokuRunner.Source, manga: AidokuRunner.Manga, needsDetails: Bool,
                       preferredLanguage: String?) async throws -> AidokuRunner.Manga {
        var fetched = try await source.getMangaUpdate(manga: manga, needsDetails: needsDetails, needsChapters: true)
        try Task.checkCancellation()
        guard fetched.identifier == manga.identifier else { throw LanguageError.mismatchedTitle }
        if let language = SumiChapterLanguage.normalized(preferredLanguage), supports(source),
           (source.runner is HonbakoMangaDexRunner || Self.providerLanguage(for: language, advertisedLanguages: source.languages) != nil),
           !(fetched.chapters ?? []).contains(where: { SumiChapterLanguage.normalized($0.language) == language }) {
            let translated = try await load(source: source, manga: manga, language: language)
            fetched.chapters = SumiChapterLanguage.retainingOtherLanguages(existing: fetched.chapters ?? [], fetched: translated)
        }
        return SumiMangaMetadata.merging(manga, with: fetched)
    }

    static func supports(_ source: AidokuRunner.Source) -> Bool {
        if source.runner is HonbakoMangaDexRunner { return true }
        return !translationLanguages(sourceKey: source.key, advertisedLanguages: source.languages, hasPackage: source.url != nil).isEmpty
    }

    /// Source.languages can describe its entire catalog, not editions of one
    /// title. Only advertise unfetched editions for reviewed per-title chapter
    /// language contracts. Other sources still expose actual chapter labels.
    static func translationLanguages(sourceKey: String, advertisedLanguages: [String], hasPackage: Bool) -> [String] {
        guard hasPackage, ["multi.mangadex", "multi.mangafire"].contains(sourceKey) else { return [] }
        let values = Array(Set(advertisedLanguages.compactMap(SumiChapterLanguage.normalized)))
        return values.count > 1 ? values : []
    }

    static func offeredLanguages(chapters: [AidokuRunner.Chapter], sourceKey: String,
                                 advertisedLanguages: [String], hasPackage: Bool,
                                 nativeTitleLanguages: [String] = []) -> [String] {
        let additional = sourceKey == HonbakoMangaDexRunner.sourceKey ? nativeTitleLanguages
            : translationLanguages(sourceKey: sourceKey, advertisedLanguages: advertisedLanguages, hasPackage: hasPackage)
        return Array(Set(SumiChapterLanguage.languages(in: chapters) + additional.compactMap(SumiChapterLanguage.normalized)))
            .sorted {
                let comparison = SourceLanguage.displayName(for: $0).localizedStandardCompare(SourceLanguage.displayName(for: $1))
                return comparison == .orderedSame ? $0 < $1 : comparison == .orderedAscending
            }
    }

    /// Pass the source's advertised value to its settings, even when its chapter
    /// responses use an alias. The provider owns conversion to its API codes.
    static func providerLanguage(for language: String, advertisedLanguages: [String]) -> String? {
        guard let requested = SumiChapterLanguage.normalized(language) else { return nil }
        return advertisedLanguages.first { SumiChapterLanguage.normalized($0) == requested }
    }

    static func load(source: AidokuRunner.Source, manga: AidokuRunner.Manga, language: String) async throws -> [AidokuRunner.Chapter] {
        if let native = source.runner as? HonbakoMangaDexRunner {
            return try await native.chapters(for: manga, language: language)
        }
        guard let package = source.url, supports(source),
              let providerLanguage = Self.providerLanguage(for: language, advertisedLanguages: source.languages) else {
            throw LanguageError.unsupported
        }
        let scope = SumiLanguagePreferenceScope(sourceKey: source.key, language: providerLanguage)
        defer { scope.remove() }
        let executable = package.appendingPathComponent("main.wasm")
        let bytes = try await Task.detached(priority: .userInitiated) { [UInt8](try Data(contentsOf: executable)) }.value
        try Task.checkCancellation()
        let interpreter = try await Interpreter(sourceKey: scope.namespace, bytes: bytes,
            config: .init(printHandler: { _ in }))
        let result = try await interpreter.getMangaUpdate(manga: manga, needsDetails: false, needsChapters: true)
        try Task.checkCancellation()
        guard result.key == manga.key || result.key.isEmpty else { throw LanguageError.mismatchedTitle }
        // The source may ignore a language selection. Never relabel another
        // explicit translation as the requested one.
        return SumiChapterLanguage.filter(result.chapters ?? [], language: language)
    }

    private enum LanguageError: LocalizedError {
        case unsupported, mismatchedTitle
        var errorDescription: String? {
            switch self {
            case .unsupported: "This source doesn’t provide another language for this title."
            case .mismatchedTitle: "The source returned a different title. Your current chapter is unchanged."
            }
        }
    }
}

/// Owned by one fetch. No writes ever target the installed source's defaults.
final class SumiLanguagePreferenceScope: @unchecked Sendable {
    let namespace: String
    private let defaults: UserDefaults

    init(sourceKey: String, language: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        namespace = "Sumi.LanguageSession.\(UUID().uuidString)"
        let prefix = sourceKey + "."
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
            defaults.set(value, forKey: namespace + "." + key.dropFirst(prefix.count))
        }
        defaults.set(language, forKey: namespace + ".language")
        defaults.set([language], forKey: namespace + ".languages")
    }

    func remove() {
        let prefix = namespace + "."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    deinit { remove() }

    /// Run only at launch, before any language request can be active.
    static func removeAbandoned(in defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("Sumi.LanguageSession.") {
            defaults.removeObject(forKey: key)
        }
    }
}
#endif
