#if SUMI
import AidokuRunner
import CoreData
import UIKit

/// First-party, fully bundled reading lesson. Removing it is a lasting choice.
@MainActor
enum HonbakoTutorialManga {
    nonisolated static let sourceKey = "honbako.tutorial"
    nonisolated static let mangaKey = "first-chapter"
    nonisolated static let languages = ["en", "ja", "zh-Hans", "zh-Hant"]
    private static let seedKey = "Honbako.Tutorial.Installed.v1"
    private static var installation: Task<Void, Never>?
    static let source = AidokuRunner.Source(key: sourceKey, name: String(localized: "On This Device"), version: 3,
        languages: languages, contentRating: .safe, staticListings: [], runner: HonbakoTutorialRunner())

    static func ensureInstalled() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--sumi-grid-check") || HonbakoCatalogPreviewFixtures.isEnabled { return }
        #endif
        if let installation { await installation.value; return }
        let task = Task { @MainActor in
            do {
                let manga = try makeManga()
                let previouslyInstalled = UserDefaults.standard.bool(forKey: seedKey)
                let preferred = language(for: Locale.preferredLanguages.first ?? "en")
                let installed = try await CoreDataManager.shared.container.performBackgroundTask { context in
                    let manager = CoreDataManager.shared
                    let existing = manager.getManga(mangaId: manga.identifier, context: context)
                    if previouslyInstalled, existing?.libraryObject == nil { return false }
                    if existing?.libraryObject == nil {
                        manager.addToLibrary(manga: manga, chapters: manga.chapters ?? [], context: context)
                        manager.getManga(mangaId: manga.identifier, context: context)?.langFilter = preferred
                    } else if existing?.cover != manga.cover || existing?.title != manga.title {
                        existing?.load(from: manga)
                        manager.setChapters(manga.chapters ?? [], mangaId: manga.identifier, context: context)
                    }
                    if context.hasChanges { try context.save() }
                    return true
                }
                if installed { UserDefaults.standard.set(true, forKey: seedKey) }
            } catch {
                LogManager.logger.error("Bundled tutorial setup failed: \(error.localizedDescription)")
            }
            await HonbakoGuideLibrary.ensureInstalled()
        }
        installation = task
        await task.value
        installation = nil
    }

    nonisolated static func language(for identifier: String) -> String {
        if identifier.hasPrefix("ja") { return "ja" }
        if ["zh-Hant", "zh-TW", "zh-HK", "zh-MO"].contains(where: { identifier.hasPrefix($0) }) { return "zh-Hant" }
        if identifier.hasPrefix("zh") { return "zh-Hans" }
        return "en"
    }

    static func makeManga() throws -> AidokuRunner.Manga {
        let language = language(for: Locale.preferredLanguages.first ?? "en")
        let cover = try renderedFile(art: "HonbakoTutorialCoverArt", language: language,
            title: "Tutorial.Story.Title", body: "Tutorial.Story.CoverSubtitle", file: "cover.png", cover: true)
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 27))
        let chapters = languages.map {
            AidokuRunner.Chapter(key: "\($0)-first-chapter", title: text("Tutorial.Story.Title", language: $0),
                chapterNumber: 1, dateUploaded: date, language: $0)
        }
        return .init(sourceKey: sourceKey, key: mangaKey, title: text("Tutorial.Story.Title", language: language),
            cover: cover.absoluteString, authors: ["Honbako"],
            description: text("An original story about a bookseller, a curious cat, and your next favorite book.", language: language),
            status: .completed, contentRating: .safe, viewer: .rightToLeft, updateStrategy: .never, chapters: chapters)
    }

    static func pages(for chapter: AidokuRunner.Chapter) throws -> [AidokuRunner.Page] {
        guard let language = languages.first(where: { chapter.key == "\($0)-first-chapter" }) else {
            throw URLError(.resourceUnavailable)
        }
        let lessons = [
            ("HonbakoTutorialPage1Art", "Tutorial.Story.Empty.Title", "Tutorial.Story.Empty.Body"),
            ("HonbakoTutorialSourcesArt", "Tutorial.Story.Key.Title", "Tutorial.Story.Key.Body"),
            ("HonbakoTutorialCollectionArt", "Tutorial.Story.Door.Title", "Tutorial.Story.Door.Body"),
            ("HonbakoTutorialPage2Art", "Tutorial.Story.Read.Title", "Tutorial.Story.Read.Body"),
            ("HonbakoTutorialReturnArt", "Tutorial.Story.Bookmark.Title", "Tutorial.Story.Bookmark.Body"),
            ("HonbakoTutorialPage3Art", "Tutorial.Story.Morning.Title", "Tutorial.Story.Morning.Body")
        ]
        return try lessons.enumerated().map { index, lesson in
            let url = try renderedFile(art: lesson.0, language: language,
                title: lesson.1, body: lesson.2, file: "page-\(index + 1).png", cover: false)
            return AidokuRunner.Page(content: .url(url: url), thumbnail: url,
                description: text(lesson.1, language: language))
        }
    }

    private static func text(_ key: String, language: String) -> String {
        let bundle = Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    private static func renderedFile(art name: String, language: String, title: String, body: String,
                                     file: String, cover: Bool) throws -> URL {
        let folder = FileManager.default.applicationSupportDirectory
            .appendingPathComponent("HonbakoTutorial/v3/\(language)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        var location = folder; try? location.setResourceValues(excluded)
        let url = folder.appendingPathComponent(file)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let art = UIImage(named: name) else { throw URLError(.fileDoesNotExist) }
        let size = CGSize(width: 1024, height: 1536)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let page = UIGraphicsImageRenderer(size: size, format: format).image { output in
            UIColor.white.setFill(); output.fill(CGRect(origin: .zero, size: size))
            art.draw(in: CGRect(origin: .zero, size: size))
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            let heading = text(title, language: language)
            let detail = text(body, language: language)
            (heading as NSString).draw(in: CGRect(x: 64, y: 1200, width: 896, height: cover ? 140 : 72),
                withAttributes: [.font: UIFont.systemFont(ofSize: cover ? 58 : 44, weight: .bold),
                    .foregroundColor: UIColor.black, .paragraphStyle: paragraph])
            (detail as NSString).draw(in: CGRect(x: 72, y: cover ? 1360 : 1280, width: 880, height: cover ? 148 : 230),
                withAttributes: [.font: UIFont.systemFont(ofSize: cover ? 34 : 30, weight: .regular),
                    .foregroundColor: UIColor.black, .paragraphStyle: paragraph])
        }
        guard let data = page.pngData() else { throw URLError(.cannotDecodeContentData) }
        try data.write(to: url, options: .atomic)
        return url
    }
}
#endif
