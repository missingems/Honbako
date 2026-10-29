#if SUMI
import AidokuRunner
import CoreData
import UIKit

@MainActor
enum HonbakoGuideLibrary {
    static let searchEnabledKey = "Honbako.Guides.IncludedInSearch"
    static func ensureInstalled() async {
        for guide in HonbakoGuideBook.allCases {
            do {
                let manga = try makeManga(guide)
                let previouslyInstalled = UserDefaults.standard.bool(forKey: guide.seedKey)
                let preferred = HonbakoTutorialManga.language(for: Locale.preferredLanguages.first ?? "en")
                try await CoreDataManager.shared.container.performBackgroundTask { context in
                    let manager = CoreDataManager.shared
                    let existing = manager.getManga(mangaId: manga.identifier, context: context)
                    if HonbakoGuideBook.shouldInstall(previouslyInstalled: previouslyInstalled, isInLibrary: existing?.libraryObject != nil) {
                        manager.addToLibrary(manga: manga, chapters: manga.chapters ?? [], context: context)
                        manager.getManga(mangaId: manga.identifier, context: context)?.langFilter = preferred
                    } else if existing?.libraryObject != nil, existing?.cover != manga.cover || existing?.title != manga.title {
                        existing?.load(from: manga)
                        manager.setChapters(manga.chapters ?? [], mangaId: manga.identifier, context: context)
                    }
                    if context.hasChanges { try context.save() }
                }
                UserDefaults.standard.set(true, forKey: guide.seedKey)
            } catch {
                LogManager.logger.error("Bundled guide setup failed: \(error.localizedDescription)")
            }
        }
    }

    static func makeManga(_ guide: HonbakoGuideBook) throws -> AidokuRunner.Manga {
        let language = HonbakoTutorialManga.language(for: Locale.preferredLanguages.first ?? "en")
        let cover = try HonbakoGuideRenderer.file(guide: guide, page: nil, language: language)
        let chapters = HonbakoTutorialManga.languages.map { language in
            AidokuRunner.Chapter(key: "\(language)-\(guide.rawValue)", title: text(guide.prefix + ".Title", language: language),
                chapterNumber: 1, language: language)
        }
        return .init(sourceKey: HonbakoTutorialManga.sourceKey, key: guide.rawValue,
            title: text(guide.prefix + ".Title", language: language), cover: cover.absoluteString,
            authors: ["Honbako"], description: text(guide.prefix + ".Subtitle", language: language),
            status: .completed, contentRating: .safe, viewer: .rightToLeft, updateStrategy: .never, chapters: chapters)
    }

    static func pages(guide: HonbakoGuideBook, chapter: AidokuRunner.Chapter) throws -> [AidokuRunner.Page] {
        guard let language = HonbakoTutorialManga.languages.first(where: { chapter.key == "\($0)-\(guide.rawValue)" }) else {
            throw URLError(.resourceUnavailable)
        }
        return try (1...HonbakoGuideBook.pageCount).map { page in
            let url = try HonbakoGuideRenderer.file(guide: guide, page: page, language: language)
            return .init(content: .url(url: url), thumbnail: url,
                description: text("\(guide.prefix).\(page).Title", language: language))
        }
    }

    static func text(_ key: String, language: String) -> String {
        let bundle = Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
#endif
