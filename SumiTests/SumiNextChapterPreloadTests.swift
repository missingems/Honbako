@testable import Sumi
import AidokuRunner
import Foundation
import Nuke
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiNextChapterPreloadTests {
    @Test("Next-chapter preparation starts in the last three actual pages, including a visible spread")
    func threshold() {
        #expect(!SumiNextChapterPreloadPolicy.shouldPrepare(page: 4, total: 8))
        #expect(SumiNextChapterPreloadPolicy.shouldPrepare(page: 5, total: 8))
        #expect(SumiNextChapterPreloadPolicy.shouldPrepare(page: 4, total: 8, visibleCount: 2))
        #expect(SumiNextChapterPreloadPolicy.shouldPrepare(page: 1, total: 3))
        #expect(!SumiNextChapterPreloadPolicy.shouldPrepare(page: 0, total: 8))
        #expect(!SumiNextChapterPreloadPolicy.shouldPrepare(page: 1, total: 0))
    }

    @Test("Concurrent preload and actual opening share one source request without changing the visible chapter early")
    func sharedRequestAndHandoff() async throws {
        let model = makeModel()
        let current = AidokuRunner.Chapter(key: "current")
        let next = AidokuRunner.Chapter(key: "next-es", language: "es")
        model.chapter = current
        model.pages = pages(for: current)
        var pending: CheckedContinuation<[Sumi.Page], Never>?
        var requested: [String] = []
        model.sumiPageLoaderOverride = { chapter in
            requested.append(chapter.key)
            return await withCheckedContinuation { pending = $0 }
        }
        let first = Task { await model.preload(chapter: next) }
        try await wait { pending != nil }
        let second = Task { await model.preload(chapter: next) }
        let opening = Task { await model.loadPages(chapter: next) }
        await Task.yield()
        #expect(requested == [next.key])
        #expect(model.chapter?.id == current.id)
        #expect(model.pages.first?.chapterId == current.key)
        pending?.resume(returning: pages(for: next))
        #expect((await first.value).count == 1)
        #expect((await second.value).count == 1)
        #expect(await opening.value)
        #expect(model.chapter?.id == next.id)
        #expect(model.pages.first?.chapterId == next.key)
        #expect(requested == [next.key])
    }

    @Test("A canceled old preparation cannot replace a newly selected neighboring chapter")
    func stalePreparation() async throws {
        let model = makeModel()
        let current = AidokuRunner.Chapter(key: "current")
        let old = AidokuRunner.Chapter(key: "old")
        let next = AidokuRunner.Chapter(key: "next")
        model.chapter = current
        model.pages = pages(for: current)
        var pending: [String: CheckedContinuation<[Sumi.Page], Never>] = [:]
        model.sumiPageLoaderOverride = { chapter in
            await withCheckedContinuation { pending[chapter.key] = $0 }
        }
        let stale = Task { await model.preload(chapter: old) }
        try await wait { pending[old.key] != nil }
        model.sumiCancelPreload()
        let live = Task { await model.preload(chapter: next) }
        try await wait { pending[next.key] != nil }
        pending[old.key]?.resume(returning: pages(for: old))
        #expect((await stale.value).isEmpty)
        #expect(model.preloadedChapter == nil)
        pending[next.key]?.resume(returning: pages(for: next))
        #expect((await live.value).count == 1)
        #expect(model.preloadedChapter?.id == next.id)
        #expect(model.chapter?.id == current.id)
        #expect(model.pages.first?.chapterId == current.key)
    }

    @Test("A failed speculative request does not poison a real chapter open")
    func failedPreparationCanRetryOnOpen() async {
        let model = makeModel()
        let next = AidokuRunner.Chapter(key: "retry")
        var attempts = 0
        model.sumiPageLoaderOverride = { chapter in
            attempts += 1
            return attempts == 1 ? [] : self.pages(for: chapter)
        }
        #expect((await model.preload(chapter: next)).isEmpty)
        #expect(model.preloadedChapter == nil)
        #expect(await model.loadPages(chapter: next))
        #expect(model.pages.count == 1)
        #expect(attempts == 2)
    }

    @Test("Paged nearing-end preparation uses the delegate's translated next chapter exactly once and never reports it as read")
    func pagedControllerPreparation() async throws {
        let current = AidokuRunner.Chapter(key: "current-es", language: "es")
        let next = AidokuRunner.Chapter(key: "next-es", language: "es")
        let store = ReaderTemporaryPageStore()
        let reader = ReaderPagedViewController(source: nil,
            manga: .init(sourceKey: "prefetch-test", key: "controller", title: "Prefetch"), temporaryPageStore: store)
        let holding = SumiNextChapterHolding(next: next)
        reader.delegate = holding
        reader.chapter = current
        reader.viewModel.chapter = current
        reader.viewModel.pages = pages(for: current, count: 8)
        var requests: [String] = []
        reader.viewModel.sumiPageLoaderOverride = { chapter in
            requests.append(chapter.key)
            return self.pages(for: chapter)
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 450, height: 800))
        window.rootViewController = reader
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; Task { await store.removeAll() } }
        reader.loadPageControllers(chapter: current)
        reader.sumiMove(toCanonicalPage: 1)
        reader.preloadNextChapter(pageCount: 6)
        await Task.yield()
        #expect(requests.isEmpty)
        reader.sumiMove(toCanonicalPage: 6)
        try await wait { reader.viewModel.preloadedChapter?.id == next.id }
        reader.preloadNextChapter(pageCount: 6)
        await Task.yield()
        #expect(requests == [next.key])
        #expect(reader.chapter?.id == current.id)
        #expect(reader.viewModel.chapter?.id == current.id)
        #expect(reader.sumiCurrentCanonicalPage == 6)
        #expect(holding.chapterChanges.isEmpty)
        #expect(holding.reports.allSatisfy { (1...8).contains($0) })
        holding.next = nil
        reader.setChapter(next, startPage: 1)
        try await wait { reader.viewModel.chapter?.id == next.id }
        #expect(requests == [next.key], "Opening consumes the prefetched list instead of issuing another request")
    }

    @Test("Prepared file pages are actually decoded into the same pipeline's memory cache")
    func decodedImageWarmup() async throws {
        let cache = ImageCache()
        var configuration = ImagePipeline.Configuration()
        configuration.imageCache = cache
        let pipeline = ImagePipeline(configuration: configuration)
        let prefetcher = ReaderPagePrefetcher(decodedImages: true, pipeline: pipeline)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        try image().pngData()!.write(to: url)
        defer { prefetcher.reset(); try? FileManager.default.removeItem(at: url) }
        let page = Sumi.Page(sourceId: "prefetch-test", chapterId: "next", index: 0, imageURL: url.absoluteString)
        await prefetcher.prefetch(pages: [page], count: 3, chapterKey: "next", sourceKey: "prefetch-test")
        try await wait { cache.totalCount > 0 }
        #expect(cache.totalCost > 0)
    }

    @Test("A controller retries a transient next-chapter failure after a bounded quiet period")
    func controllerRetriesFailedPreparation() async throws {
        let current = AidokuRunner.Chapter(key: "retry-current")
        let next = AidokuRunner.Chapter(key: "retry-next")
        let store = ReaderTemporaryPageStore()
        let reader = ReaderPagedViewController(source: nil,
            manga: .init(sourceKey: "prefetch-test", key: "retry-controller", title: "Retry"), temporaryPageStore: store)
        let holding = SumiNextChapterHolding(next: next)
        reader.delegate = holding
        reader.chapter = current
        reader.viewModel.chapter = current
        reader.viewModel.pages = pages(for: current, count: 8)
        var attempts = 0
        reader.viewModel.sumiPageLoaderOverride = { chapter in
            attempts += 1
            return attempts == 1 ? [] : self.pages(for: chapter)
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 450, height: 800))
        window.rootViewController = reader
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; Task { await store.removeAll() } }
        reader.loadPageControllers(chapter: current)
        reader.sumiMove(toCanonicalPage: 6)
        try await wait { attempts == 1 }
        for _ in 0..<10 { await Task.yield() }
        for _ in 0..<10 { reader.preloadNextChapter(pageCount: 3) }
        await Task.yield()
        #expect(attempts == 1, "Scroll/layout updates must not hammer a temporarily unavailable source")
        try await Task.sleep(for: .seconds(SumiNextChapterPreloadPolicy.retryDelay + 0.05))
        reader.preloadNextChapter(pageCount: 3)
        try await wait { reader.viewModel.preloadedChapter?.id == next.id }
        #expect(attempts == 2)
        #expect(reader.viewModel.chapter?.id == current.id)
        #expect(reader.sumiCurrentCanonicalPage == 6)
        #expect(holding.chapterChanges.isEmpty)
    }

    private func makeModel() -> ReaderPagedViewModel {
        ReaderPagedViewModel(source: nil, manga: .init(sourceKey: "prefetch-test", key: UUID().uuidString, title: "Prefetch"))
    }

    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
    }

    private func pages(for chapter: AidokuRunner.Chapter, count: Int = 1) -> [Sumi.Page] {
        (0..<count).map { Sumi.Page(sourceId: "prefetch-test", chapterId: chapter.key, index: $0, image: image()) }
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }
}

@MainActor
private final class SumiNextChapterHolding: ReaderHoldingDelegate {
    var next: AidokuRunner.Chapter?
    var barsHidden = true
    var reports: [Int] = []
    var chapterChanges: [String] = []
    init(next: AidokuRunner.Chapter) { self.next = next }
    func getNextChapter() -> AidokuRunner.Chapter? { next }
    func getPreviousChapter() -> AidokuRunner.Chapter? { nil }
    func setChapter(_ chapter: AidokuRunner.Chapter) { chapterChanges.append(chapter.key) }
    func hideBars() {}
    func setCurrentPage(_ page: Int, position: Double?) { reports.append(page) }
    func setCurrentPages(_ pages: ClosedRange<Int>) { reports.append(contentsOf: pages) }
    func setPages(_ pages: [Sumi.Page]) {}
    func displayPage(_ page: Int) {}
    func setSliderOffset(_ offset: CGFloat) {}
    func setCompleted() {}
}
