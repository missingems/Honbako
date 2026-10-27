@testable import Sumi
import AidokuRunner
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiChapterBoundaryTests {
    @Test("Chapter boundaries show a quiet end without naming or linking an adjacent chapter")
    func nextAndEndStates() {
        let view = SumiChapterBoundaryView()
        var continued = false
        view.onContinue = { continued = true }
        view.update(type: .next, destination: .init(key: "second", chapterNumber: 2))
        #expect(view.titleLabel.text == "Chapter End")
        #expect(view.detailLabel.text == nil && view.detailLabel.isHidden)
        #expect(view.continueButton.isHidden)
        view.continueButton.sendActions(for: .touchUpInside)
        #expect(!continued, "An old chapter-link action must not survive on the quiet boundary")
        view.update(type: .next, destination: nil)
        #expect(view.titleLabel.text == "Chapter End")
        #expect(view.continueButton.isHidden)
        #expect(view.detailLabel.text == nil)
        view.update(type: .previous, destination: .init(key: "first", chapterNumber: 1))
        #expect(view.titleLabel.text == "Chapter 1 End")
        #expect(view.detailLabel.text == nil && view.continueButton.isHidden)
        view.update(type: .previous, destination: nil)
        #expect(view.titleLabel.text == "The Beginning")
    }

    @Test("A failed chapter keeps retry available without leaking it into the normal page boundary")
    func failureCanRetryThenReturnToQuietEnd() {
        let view = SumiChapterBoundaryView()
        var retries = 0
        view.showError { retries += 1 }
        #expect(view.titleLabel.text == "Chapter Unavailable")
        #expect(!view.continueButton.isHidden)
        #expect(view.continueButton.configuration?.title == "Try Again")
        view.continueButton.sendActions(for: .touchUpInside)
        #expect(retries == 1)
        view.update(type: .next, destination: .init(key: "second", chapterNumber: 2))
        #expect(view.titleLabel.text == "Chapter End")
        #expect(view.detailLabel.isHidden && view.continueButton.isHidden)
        view.continueButton.sendActions(for: .touchUpInside)
        #expect(retries == 1)
    }

    @Test("Both sides of a chapter boundary name the chapter that actually finished")
    func numberedEnd() {
        let view = SumiChapterBoundaryView()
        let current = AidokuRunner.Chapter(key: "current", chapterNumber: 53.5)
        let next = AidokuRunner.Chapter(key: "next", chapterNumber: 54)
        view.update(type: .next, currentChapter: current, destination: next)
        #expect(view.titleLabel.text == "Chapter 53.5 End")
        view.update(type: .previous, currentChapter: next, destination: current)
        #expect(view.titleLabel.text == "Chapter 53.5 End")
    }

    @Test("A landscape chapter end has its next cover on the right and continues at page two", arguments: [ReadingMode.rtl, .ltr])
    func landscapeBoundaryHandoff(mode: ReadingMode) async throws {
        let fixture = makeReader(mode: mode, size: CGSize(width: 1000, height: 700))
        defer { fixture.close() }
        let reader = fixture.reader
        reader.move(toPage: 4, animated: false)
        try await wait { reader.pageViewControllers.last?.page?.chapterId == fixture.next.key }
        let cover = try #require(reader.pageViewControllers.last)
        let pager = try pager(in: reader)
        let current = try #require(pager.viewControllers?.first)
        let boundary = try #require(reader.getPageController(after: current) as? ReaderBookSpreadViewController)
        #expect(boundary.leaves[0] === reader.pageViewControllers[5])
        #expect(boundary.leaves[1] === cover)
        #expect(labels(in: boundary.leaves[0].view).contains("Chapter 53 End"))
        #expect(cover.page?.index == 0)
        #expect(fixture.holding.chapterChanges.isEmpty, "Preparing a boundary must not select its next chapter")

        advance(reader, mode: mode)
        try await wait { reader.viewModel.chapter?.id == fixture.next.id && reader.currentPage == 1 }
        let nextPager = try self.pager(in: reader)
        let opening = try #require(nextPager.viewControllers?.first as? ReaderBookSpreadViewController)
        #expect(labels(in: opening.leaves[0].view).contains("Chapter 53 End"))
        #expect(opening.leaves[1] === cover, "The preview must become the actual cover without replacing its artwork")
        #expect(reader.visibleActualPageRange(in: opening) == 1...1)
        #expect(fixture.holding.chapterChanges == [fixture.next.key])
        #expect(fixture.requests.keys == [fixture.next.key])
        #expect(await reader.sumiPrepareCanonicalPage(1), "A text boundary must not be mistaken for unloaded artwork")
        #expect(reader.sumiReadyForOpening)

        advance(reader, mode: mode)
        #expect(reader.currentPage == 2)
        let second = try #require((try self.pager(in: reader)).viewControllers)
        #expect(reader.visibleActualPageRange(in: second) == 2...3)
        #expect(reader.pageViewControllers[3].page?.index == 1)
        #expect(reader.pageViewControllers[4].page?.index == 2)
        #expect(fixture.holding.reports.filter { $0.chapter == fixture.next.key }.allSatisfy { $0.pages.lowerBound >= 1 })

        // A fold keeps the selected canonical page rather than jumping back to
        // the previous end or re-showing the next chapter's cover.
        fixture.window.frame.size = CGSize(width: 450, height: 800)
        try await settle(reader, window: fixture.window)
        #expect(reader.sumiCurrentCanonicalPage == 2)
        #expect(reader.currentPage == 2)
        let portrait = try self.pager(in: reader)
        #expect(!(portrait is SumiPageCurlViewController))
        #expect(reader.visibleActualPageRange(in: try #require(portrait.viewControllers)) == 2...2)
    }

    @Test("Portrait swipes from the numbered end directly to the next cover, then page two")
    func portraitBoundaryHandoff() async throws {
        let fixture = makeReader(mode: .rtl, size: CGSize(width: 450, height: 800))
        defer { fixture.close() }
        let reader = fixture.reader
        reader.move(toPage: 4, animated: false)
        try await wait { reader.pageViewControllers.last?.page?.chapterId == fixture.next.key }
        reader.moveLeft()
        #expect(reader.currentPage == 5)
        #expect(reader.chapter?.id == fixture.current.id)
        #expect(fixture.holding.chapterChanges.isEmpty)
        let endPager = try pager(in: reader)
        #expect(labels(in: try #require(endPager.viewControllers?.first).view).contains("Chapter 53 End"))
        reader.moveLeft()
        try await wait { reader.viewModel.chapter?.id == fixture.next.id && reader.currentPage == 1 }
        let opened = try self.pager(in: reader)
        let cover = try #require(opened.viewControllers?.first as? ReaderPageViewController)
        #expect(cover.page?.chapterId == fixture.next.key && cover.page?.index == 0)
        reader.moveLeft()
        #expect(reader.currentPage == 2)
        #expect(reader.visibleActualPageRange(in: try #require(opened.viewControllers)) == 2...2)
        #expect(fixture.requests.keys == [fixture.next.key])
    }

    private func makeReader(mode: ReadingMode, size: CGSize) -> BoundaryFixture {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var settings = original
        settings["Reader.pagedPageLayout"] = "auto"
        settings["Reader.splitWideImages"] = false
        settings["Reader.pagedPageOffset"] = false
        settings["Reader.animatePageTransitions"] = false
        defaults.setVolatileDomain(settings, forName: UserDefaults.argumentDomain)
        let current = AidokuRunner.Chapter(key: "boundary-current", chapterNumber: 53)
        let next = AidokuRunner.Chapter(key: "boundary-next", chapterNumber: 54)
        let holding = BoundaryHolding(current: current, next: next)
        let store = ReaderTemporaryPageStore()
        let reader = ReaderPagedViewController(source: nil,
            manga: .init(sourceKey: "boundary-test", key: "book", title: "Boundary"), temporaryPageStore: store)
        let requests = BoundaryRequests()
        reader.delegate = holding
        reader.readingMode = mode
        reader.chapter = current
        reader.viewModel.chapter = current
        reader.viewModel.pages = pages(for: current, count: 4)
        reader.viewModel.sumiPageLoaderOverride = { chapter in
            requests.keys.append(chapter.key)
            return pages(for: chapter, count: chapter.id == next.id ? 5 : 4)
        }
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = reader
        window.isHidden = false
        reader.loadPageControllers(chapter: current)
        reader.loadPages(in: 1...4)
        reader.view.layoutIfNeeded()
        return BoundaryFixture(reader: reader, window: window, holding: holding, store: store,
            current: current, next: next, requests: requests, defaults: original)
    }

    private func pages(for chapter: AidokuRunner.Chapter, count: Int) -> [Sumi.Page] {
        (0..<count).map { index in
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 120), format: format).image { context in
                UIColor(white: CGFloat(index + 1) / CGFloat(count + 1), alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
            }
            return Sumi.Page(sourceId: "boundary-test", chapterId: chapter.key, index: index, image: image)
        }
    }

    private func advance(_ reader: ReaderPagedViewController, mode: ReadingMode) {
        if mode == .rtl { reader.moveLeft() } else { reader.moveRight() }
    }

    private func labels(in view: UIView) -> [String] {
        (view as? UILabel).flatMap(\.text).map { [$0] } ?? view.subviews.flatMap { labels(in: $0) }
    }

    private func pager(in reader: ReaderPagedViewController) throws -> UIPageViewController {
        try #require(reader.children.compactMap { $0 as? UIPageViewController }.first)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }

    private func settle(_ reader: ReaderPagedViewController, window: UIWindow) async throws {
        for _ in 0..<4 {
            window.setNeedsLayout(); reader.view.setNeedsLayout()
            window.layoutIfNeeded(); reader.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
    }
}

@MainActor
private final class BoundaryRequests {
    var keys: [String] = []
}

@MainActor
private struct BoundaryFixture {
    let reader: ReaderPagedViewController
    let window: UIWindow
    let holding: BoundaryHolding
    let store: ReaderTemporaryPageStore
    let current: AidokuRunner.Chapter
    let next: AidokuRunner.Chapter
    let requests: BoundaryRequests
    let defaults: [String: Any]
    func close() {
        window.isHidden = true
        window.rootViewController = nil
        UserDefaults.standard.setVolatileDomain(defaults, forName: UserDefaults.argumentDomain)
        Task { await store.removeAll() }
    }
}

@MainActor
private final class BoundaryHolding: ReaderHoldingDelegate {
    var barsHidden = true
    var current: AidokuRunner.Chapter
    let first: AidokuRunner.Chapter
    let next: AidokuRunner.Chapter
    var chapterChanges: [String] = []
    var reports: [(chapter: String, pages: ClosedRange<Int>)] = []
    init(current: AidokuRunner.Chapter, next: AidokuRunner.Chapter) {
        self.current = current; first = current; self.next = next
    }
    func getNextChapter() -> AidokuRunner.Chapter? { current.id == first.id ? next : nil }
    func getPreviousChapter() -> AidokuRunner.Chapter? { current.id == next.id ? first : nil }
    func setChapter(_ chapter: AidokuRunner.Chapter) { current = chapter; chapterChanges.append(chapter.key) }
    func hideBars() { barsHidden = true }
    func setCurrentPage(_ page: Int, position: Double?) { reports.append((current.key, page...page)) }
    func setCurrentPages(_ pages: ClosedRange<Int>) { reports.append((current.key, pages)) }
    func setPages(_ pages: [Sumi.Page]) {}
    func displayPage(_ page: Int) {}
    func setSliderOffset(_ offset: CGFloat) {}
    func setCompleted() {}
}
