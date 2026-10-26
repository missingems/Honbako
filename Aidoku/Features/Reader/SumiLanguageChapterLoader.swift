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
           source.languages.contains(where: { SumiChapterLanguage.normalized($0) == language }),
           !(fetched.chapters ?? []).contains(where: { SumiChapterLanguage.normalized($0.language) == language }) {
            let translated = try await load(source: source, manga: manga, language: language)
            fetched.chapters = SumiChapterLanguage.retainingOtherLanguages(existing: fetched.chapters ?? [], fetched: translated)
        }
        return SumiMangaMetadata.merging(manga, with: fetched)
    }

    static func supports(_ source: AidokuRunner.Source) -> Bool {
        source.url != nil && source.languages.compactMap(SumiChapterLanguage.normalized).count > 1
    }

    static func load(source: AidokuRunner.Source, manga: AidokuRunner.Manga, language: String) async throws -> [AidokuRunner.Chapter] {
        guard let package = source.url, supports(source),
              let providerLanguage = source.languages.first(where: { SumiChapterLanguage.normalized($0) == SumiChapterLanguage.normalized(language) }) else {
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
        return (result.chapters ?? []).filter {
            SumiChapterLanguage.normalized($0.language) == SumiChapterLanguage.normalized(language)
        }
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
