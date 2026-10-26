@testable import Sumi
import AidokuRunner
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiReaderIndexTests {
    @Test("Front matter preserves canonical page identities and puts page one physically right", arguments: [ReadingMode.ltr, .rtl])
    func physicalOpening(mode: ReadingMode) async throws {
        let fixture = makeReader(mode: mode, size: CGSize(width: 1000, height: 700))
        defer { fixture.close() }
        let reader = fixture.reader
        reader.move(toPage: 1, animated: false)
        try await settle(reader, window: fixture.window)
        let pager = try pager(in: reader)
        let spread = try #require(pager.viewControllers?.first as? ReaderBookSpreadViewController)
        #expect(spread.leaves[0] is SumiIndexLeafViewController)
        #expect(spread.leaves[1] === reader.pageViewControllers[1])
        #expect(reader.viewModel.pages.count == 6)
        #expect(reader.pageViewControllers.count == 8) // Six real pages and the existing two chapter-transition controllers.
        #expect(reader.visibleActualPageRange(in: spread) == 1...1)
        #expect(fixture.delegate.reports.last == 1...1)
        let originalPages = reader.pageViewControllers
        reader.move(toPage: 2, animated: false)
        #expect(reader.visibleActualPageRange(in: try #require(pager.viewControllers)) == 2...3)
        reader.move(toPage: 1, animated: false)
        let returned = try #require(pager.viewControllers?.first as? ReaderBookSpreadViewController)
        #expect(returned.leaves[0] is SumiIndexLeafViewController)
        #expect(returned.leaves[1] === originalPages[1])
        #expect(reader.pageViewControllers.elementsEqual(originalPages, by: { $0 === $1 }))
        #expect(fixture.delegate.reports.allSatisfy { $0.lowerBound >= 1 && $0.upperBound <= 6 })
    }

    @Test("A portrait index reports no fake progress and swipes to and back from the real first page")
    func portraitIndexIsNotAChapterPage() async throws {
        let fixture = makeReader(mode: .rtl, size: CGSize(width: 450, height: 700))
        defer { fixture.close() }
        let reader = fixture.reader
        reader.move(toPage: 0, animated: false)
        try await settle(reader, window: fixture.window)
        let pager = try pager(in: reader)
        let index = try #require(pager.viewControllers?.first as? SumiIndexLeafViewController)
        #expect(!(pager is SumiPageCurlViewController))
        #expect(pager.view.accessibilityIdentifier == "sumi.reader.slide")
        #expect(reader.currentPage == 0)
        #expect(fixture.delegate.reports.isEmpty)
        #expect(reader.visibleActualPageRange(in: index) == nil)
        #expect(reader.getPageController(before: index) == nil)
        #expect(reader.getPageController(after: index) === reader.pageViewControllers[1])
        reader.move(toPage: 1, animated: false)
        #expect(fixture.delegate.reports.last == 1...1)
        #expect(reader.getPageController(before: reader.pageViewControllers[1]) === index)
        let count = fixture.delegate.reports.count
        reader.move(toPage: 0, animated: false)
        #expect(fixture.delegate.reports.count == count)
        #expect(reader.viewModel.pages.count == 6)

        fixture.window.frame.size = CGSize(width: 1000, height: 700)
        try await settle(reader, window: fixture.window)
        let wide = try self.pager(in: reader)
        let spread = try #require(wide.viewControllers?.first as? ReaderBookSpreadViewController)
        #expect(spread.leaves[0] === index)
        #expect(spread.leaves[1] === reader.pageViewControllers[1])
        #expect(reader.visibleActualPageRange(in: spread) == 1...1)
    }

    @Test("Resumed openings omit front matter and keep the requested real page")
    func resumedPageIsExact() async throws {
        let fixture = makeReader(mode: .ltr, size: CGSize(width: 450, height: 700), includeIndex: false)
        defer { fixture.close() }
        fixture.reader.move(toPage: 4, animated: false)
        try await settle(fixture.reader, window: fixture.window)
        let pager = try pager(in: fixture.reader)
        #expect(pager.viewControllers?.first === fixture.reader.pageViewControllers[4])
        #expect(fixture.reader.currentPage == 4)
        #expect(fixture.delegate.reports.last == 4...4)
    }

    private func makeReader(mode: ReadingMode, size: CGSize, includeIndex: Bool = true) -> Fixture {
        let store = ReaderTemporaryPageStore()
        let chapter = AidokuRunner.Chapter(key: "first")
        let manga = AidokuRunner.Manga(sourceKey: "sumi-index-test", key: "book", title: "Index test")
        let reader = ReaderPagedViewController(source: nil, manga: manga, temporaryPageStore: store)
        let delegate = IndexReaderDelegate()
        reader.delegate = delegate
        reader.readingMode = mode
        reader.chapter = chapter
        if includeIndex { reader.sumiOpeningIndex = SumiReaderIndex(manga: manga, chapters: [], openingChapterKey: chapter.key) }
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = reader
        window.isHidden = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
        }
        reader.viewModel.pages = (0..<6).map { .init(sourceId: manga.sourceKey, chapterId: chapter.id, index: $0, image: image) }
        reader.loadPageControllers(chapter: chapter)
        reader.loadPages(in: 1...6)
        reader.view.layoutIfNeeded()
        return Fixture(reader: reader, delegate: delegate, window: window, store: store)
    }

    private func settle(_ reader: ReaderPagedViewController, window: UIWindow) async throws {
        for _ in 0..<4 {
            window.setNeedsLayout(); reader.view.setNeedsLayout()
            window.layoutIfNeeded(); reader.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    private func pager(in reader: ReaderPagedViewController) throws -> UIPageViewController {
        try #require(reader.children.compactMap { $0 as? UIPageViewController }.first)
    }

    @MainActor private struct Fixture {
        let reader: ReaderPagedViewController
        let delegate: IndexReaderDelegate
        let window: UIWindow
        let store: ReaderTemporaryPageStore
        func close() {
            window.isHidden = true
            window.rootViewController = nil
            Task { await store.removeAll() }
        }
    }
}

@MainActor
private final class IndexReaderDelegate: ReaderHoldingDelegate {
    var barsHidden = true
    var reports: [ClosedRange<Int>] = []
    func hideBars() { barsHidden = true }
    func getNextChapter() -> AidokuRunner.Chapter? { nil }
    func getPreviousChapter() -> AidokuRunner.Chapter? { nil }
    func setChapter(_ chapter: AidokuRunner.Chapter) {}
    func setCurrentPage(_ page: Int, position: Double?) { reports.append(page...page) }
    func setCurrentPages(_ pages: ClosedRange<Int>) { reports.append(pages) }
    func setPages(_ pages: [Sumi.Page]) {}
    func displayPage(_ page: Int) {}
    func setSliderOffset(_ offset: CGFloat) {}
    func setCompleted() {}
}
