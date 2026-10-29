#if SUMI && DEBUG
import AidokuRunner
import UIKit

/// Opt-in generated content for real grid/reader UI tests. The fixture keeps
/// positions in memory and puts incognito/settings overrides in a volatile
/// argument domain, so it never adds manga or history to the user's database.
@MainActor
final class SumiGridPreviewFixtures {
    static let sourceKey = "sumi-grid-preview"
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--sumi-grid-check") }
    private static weak var active: SumiGridPreviewFixtures?
    let books: [SumiBook]
    private let directory: URL
    private let failedPageURL: URL
    private let originalArgumentDomain: [String: Any]
    private var positions: [String: (chapterKey: String, page: Int)] = ["book-002": ("chapter-2", 4)]

    init() {
        // Explicit UI validation stays awake until this test app terminates.
        UIApplication.shared.isIdleTimerDisabled = true
        let defaults = UserDefaults.standard
        originalArgumentDomain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var overrides = originalArgumentDomain
        overrides.merge([
            "General.incognitoMode": true,
            // Touch tests address the reader display; the decorative accessory
            // has its own geometry and is verified separately.
            HonbakoCoverDisplayPreferences.showCoverKey: false,
            "Reader.pagedPageLayout": "auto", "Reader.pagesToPreload": 8,
            "Reader.liveText": false, "Reader.autoScroll": false,
            "Reader.skipDuplicateChapters": false, "Reader.markDuplicateChapters": false,
            AppSettings.dictionary.enable.key: false
        ]) { _, new in new }
        defaults.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
        let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("SumiGridValidation", isDirectory: true)
        directory = fixtureDirectory
        failedPageURL = fixtureDirectory.appendingPathComponent("retry-page-\(UUID().uuidString).png")
        try? FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        books = (1...100).map { number in
            let key = String(format: "book-%03d", number)
            let title = String(format: "Fixture Manga %03d", number)
            let coverURL = fixtureDirectory.appendingPathComponent("\(key).png")
            if !FileManager.default.fileExists(atPath: coverURL.path) {
                try? Self.cover(number: number, title: title).pngData()?.write(to: coverURL)
            }
            var manga = AidokuRunner.Manga(sourceKey: Self.sourceKey, key: key, title: title)
            manga.cover = coverURL.absoluteString
            manga.authors = ["Generated fixture"]
            if number == 2 { manga.status = .ongoing }
            if number == 3 { manga.status = .completed }
            manga.description = "FIXTURE_DESCRIPTION_MUST_NOT_APPEAR"
            switch ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--sumi-grid-reading-mode=") })?.split(separator: "=").last {
            case "rtl": manga.viewer = .rightToLeft
            case "webtoon": manga.viewer = .webtoon
            case "vertical": manga.viewer = .vertical
            default: manga.viewer = .leftToRight
            }
            manga.chapters = Self.chapterList()
            if number == 2 {
                return SumiBook(manga: manga, chapterLabel: "Chapter 2", pageLabel: "Page 4 of 8", progress: 0.5,
                                isInLibrary: false, lastRead: Date(timeIntervalSince1970: 1_780_000_000),
                                bookmark: SumiBookmarkSnapshot(chapterKey: "chapter-2", page: 4, completed: false),
                                resumeDeviceLabel: "Test iPad", releaseYear: 2020)
            }
            return SumiBook(manga: manga)
        }
        Self.active = self
    }

    deinit {
        UserDefaults.standard.setVolatileDomain(originalArgumentDomain, forName: UserDefaults.argumentDomain)
        try? FileManager.default.removeItem(at: directory)
    }

    func prepareReader(for book: SumiBook) async -> SumiReaderOpening? {
        guard book.sourceKey == Self.sourceKey, let manga = books.first(where: { $0.id == book.id })?.manga else { return nil }
        let position = positions[manga.key]
        let key = position?.chapterKey ?? "chapter-1"
        guard let chapter = manga.chapters?.first(where: { $0.key == key }) else { return nil }
        return SumiReaderOpening(
            selection: SumiReaderSelection(source: nil, manga: manga, chapter: chapter, startPage: position?.page ?? 1),
            isFirstRead: position == nil
        )
    }

    func chapters(for book: SumiBook) -> [SumiChapterSnapshot] {
        let position = positions[book.manga.key]
        let openingKey = position?.chapterKey ?? "chapter-1"
        return (book.manga.chapters ?? Self.chapterList()).map { chapter in
            let current = chapter.key == openingKey
            let readChapter = Int(position?.chapterKey.split(separator: "-").last ?? "0") ?? 0
            let number = Int(chapter.chapterNumber ?? 0)
            return SumiChapterSnapshot(
                id: ChapterIdentifier(sourceKey: Self.sourceKey, mangaKey: book.manga.key, chapterKey: chapter.key),
                chapter: chapter, completed: number < readChapter,
                currentPage: current ? position?.page : nil, totalPages: 8,
                isCurrent: current, canRead: true
            )
        }
    }

    func readerDidClose(_ reader: ReaderViewController) {
        Self.recordProgress(manga: reader.manga, chapter: reader.chapter, page: reader.sumiCurrentCanonicalPage)
    }

    static func recordProgress(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter, page: Int) {
        guard isEnabled, manga.sourceKey == sourceKey, (1...8).contains(page),
              chapter.key.hasPrefix("chapter-"), let active else { return }
        active.positions[manga.key] = (chapter.key, page)
    }

    static func generatedPages(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) -> [Page]? {
        guard isEnabled, manga.sourceKey == sourceKey else { return nil }
        let chapterNumber = Int(chapter.chapterNumber ?? 1)
        return (1...8).map { page in
            if ProcessInfo.processInfo.arguments.contains("--honbako-page-failure-check"),
               manga.key == "book-002", chapter.key == "chapter-2", page == 4,
               let failedPageURL = active?.failedPageURL {
                // Exercise the real image pipeline failure, then recover this
                // same canonical page on the explicit retry action.
                return Page(sourceId: sourceKey, chapterId: chapter.id, index: page - 1,
                            imageURL: failedPageURL.absoluteString)
            }
            return Page(sourceId: sourceKey, chapterId: chapter.id, index: page - 1,
                        image: ProcessInfo.processInfo.arguments.contains("--honbako-japanese-guide-check")
                            ? HonbakoJapanesePracticePage.render() : pageImage(chapter: chapterNumber, page: page))
        }
    }

    static func recoverFailedPageIfNeeded(_ page: Page) {
        guard isEnabled, ProcessInfo.processInfo.arguments.contains("--honbako-page-failure-check"),
              let active, page.sourceId == sourceKey, page.index == 3,
              page.imageURL == active.failedPageURL.absoluteString else { return }
        try? pageImage(chapter: 2, page: 4).pngData()?.write(to: active.failedPageURL, options: .atomic)
    }

    /// Compatibility with the same opt-in page-provider seam used by previews.
    static func pages(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) -> [Page] {
        generatedPages(manga: manga, chapter: chapter) ?? []
    }

    private static func chapterList() -> [AidokuRunner.Chapter] {
        let multilingual = ProcessInfo.processInfo.arguments.contains("--sumi-grid-languages")
        return (1...3).reversed().flatMap { number -> [AidokuRunner.Chapter] in
            var chapter = AidokuRunner.Chapter(key: "chapter-\(number)", title: "Fixture chapter \(number)", chapterNumber: Float(number))
            if ProcessInfo.processInfo.arguments.contains("--honbako-japanese-guide-chinese-check") {
                chapter.language = "zh-Hans"
            } else if ProcessInfo.processInfo.arguments.contains("--honbako-japanese-guide-check") {
                chapter.language = "ja"
            }
            guard multilingual else { return [chapter] }
            chapter.language = "en"
            var translation = AidokuRunner.Chapter(key: "chapter-\(number)-es", title: "Capítulo \(number)", chapterNumber: Float(number))
            translation.language = "es"
            return [chapter, translation]
        }
    }

    private static func cover(number: Int, title: String) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 240, height: 360), format: format).image { context in
            let hue = CGFloat((number * 37) % 100) / 100
            UIColor(hue: hue, saturation: 0.57, brightness: 0.76, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 360))
            UIColor.white.withAlphaComponent(0.12).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 40, y: 110, width: 260, height: 260))
            title.draw(in: CGRect(x: 20, y: 28, width: 200, height: 95), withAttributes: [
                .font: UIFont.systemFont(ofSize: 25, weight: .bold), .foregroundColor: UIColor.white
            ])
            String(format: "%03d", number).draw(in: CGRect(x: 24, y: 190, width: 200, height: 120), withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 72, weight: .light), .foregroundColor: UIColor.white
            ])
        }
    }

    private static func pageImage(chapter: Int, page: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
            UIColor(white: 0.1, alpha: 1).setStroke()
            let panel = UIBezierPath(rect: CGRect(x: 22, y: 22, width: 556, height: 856))
            panel.lineWidth = 5
            panel.stroke()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            String(format: "CHAPTER %d", chapter).draw(in: CGRect(x: 35, y: 120, width: 530, height: 90), withAttributes: [
                .font: UIFont.systemFont(ofSize: 65, weight: .bold), .foregroundColor: UIColor.black, .paragraphStyle: paragraph
            ])
            String(format: "PAGE %02d", page).draw(in: CGRect(x: 35, y: 340, width: 530, height: 130), withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 94, weight: .bold), .foregroundColor: UIColor.black, .paragraphStyle: paragraph
            ])
            UIColor(white: 0.88, alpha: 1).setFill()
            context.fill(CGRect(x: 50, y: 600, width: 500, height: 190))
            "GENERATED READER FIXTURE".draw(in: CGRect(x: 65, y: 670, width: 470, height: 50), withAttributes: [
                .font: UIFont.systemFont(ofSize: 24, weight: .medium), .foregroundColor: UIColor.black, .paragraphStyle: paragraph
            ])
        }
    }
}
#endif
