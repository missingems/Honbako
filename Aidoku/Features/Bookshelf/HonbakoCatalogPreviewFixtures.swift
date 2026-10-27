#if SUMI && DEBUG
import AidokuRunner
import UIKit

/// Opt-in source fixtures exercise the real catalog, cover, and reader paths.
/// Nothing is installed or added to the reader's persistent source registry.
@MainActor
final class HonbakoCatalogPreviewFixtures {
    nonisolated static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--honbako-catalog-check") || arguments.contains("--honbako-catalog-empty")
    }

    static let shared = HonbakoCatalogPreviewFixtures()
    let sources: [AidokuRunner.Source]
    private let originalArgumentDomain: [String: Any]
    private let directory: URL

    private init() {
        let defaults = UserDefaults.standard
        originalArgumentDomain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var overrides = originalArgumentDomain
        overrides["General.incognitoMode"] = true
        overrides["Reader.liveText"] = false
        overrides["Reader.autoScroll"] = false
        overrides["Reader.skipDuplicateChapters"] = false
        overrides["Reader.markDuplicateChapters"] = false
        defaults.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("HonbakoCatalogValidation", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard !ProcessInfo.processInfo.arguments.contains("--honbako-catalog-empty") else {
            sources = []
            return
        }
        let chapters = (1...3).reversed().map { number in
            AidokuRunner.Chapter(key: "chapter-\(number)", title: "Fixture chapter \(number)",
                chapterNumber: Float(number), language: "en")
        }
        let pages = Dictionary(uniqueKeysWithValues: (1...3).map { chapter in
            ("chapter-\(chapter)", (1...4).map { page in
                AidokuRunner.Page(content: .image(Self.page(chapter: chapter, page: page)))
            })
        })
        let fast = Self.catalog(sourceKey: "honbako-catalog-fast", count: 24, chapters: chapters, directory: directory)
        let slow = Self.catalog(sourceKey: "honbako-catalog-slow", count: 3, chapters: chapters, directory: directory)
        sources = [
            Self.source(key: "honbako-catalog-fast", name: "Fast Catalog", books: fast, pages: pages),
            Self.source(key: "honbako-catalog-slow", name: "Slow Catalog", books: slow, pages: pages, searchDelay: .seconds(4))
        ]
    }

    deinit {
        UserDefaults.standard.setVolatileDomain(originalArgumentDomain, forName: UserDefaults.argumentDomain)
        try? FileManager.default.removeItem(at: directory)
    }

    private static func source(key: String, name: String, books: [AidokuRunner.Manga],
                               pages: [String: [AidokuRunner.Page]], searchDelay: Duration = .zero) -> AidokuRunner.Source {
        .init(key: key, name: name, version: 1, languages: ["en"], contentRating: .safe,
            staticListings: [.init(id: "popular", name: "Popular")],
            runner: HonbakoCatalogPreviewRunner(books: books, pages: pages, searchDelay: searchDelay))
    }

    private static func catalog(sourceKey: String, count: Int, chapters: [AidokuRunner.Chapter],
                                directory: URL) -> [AidokuRunner.Manga] {
        (0...count).map { number in
            let key = number == 0 ? "shared-title" : String(format: "book-%03d", number)
            let title = number == 0 ? "Shared Manga" : String(format: "Fixture Manga %03d", number)
            let cover = directory.appendingPathComponent("\(sourceKey)-\(key).png")
            try? Self.cover(number: number, title: title).pngData()?.write(to: cover)
            return .init(sourceKey: sourceKey, key: key, title: title, cover: cover.absoluteString,
                authors: ["Catalog Fixture Author"], status: .ongoing, viewer: .rightToLeft, chapters: chapters)
        }
    }

    private static func cover(number: Int, title: String) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 240, height: 360), format: format).image { context in
            UIColor(hue: CGFloat((number * 17 + 48) % 100) / 100,
                saturation: 0.78, brightness: 0.72, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 360))
            title.draw(in: CGRect(x: 18, y: 24, width: 204, height: 100), withAttributes: [
                .font: UIFont.systemFont(ofSize: 26, weight: .bold), .foregroundColor: UIColor.white
            ])
            "CATALOG".draw(in: CGRect(x: 18, y: 270, width: 204, height: 50), withAttributes: [
                .font: UIFont.systemFont(ofSize: 26, weight: .medium), .foregroundColor: UIColor.white
            ])
        }
    }

    private static func page(chapter: Int, page: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
            UIColor.black.setStroke()
            context.cgContext.setLineWidth(6)
            context.cgContext.stroke(CGRect(x: 24, y: 24, width: 552, height: 852))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            "CHAPTER \(chapter)".draw(in: CGRect(x: 40, y: 180, width: 520, height: 100), withAttributes: [
                .font: UIFont.systemFont(ofSize: 64, weight: .bold), .foregroundColor: UIColor.black, .paragraphStyle: paragraph
            ])
            "PAGE \(page)".draw(in: CGRect(x: 40, y: 400, width: 520, height: 130), withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 80, weight: .bold), .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ])
        }
    }
}
#endif
