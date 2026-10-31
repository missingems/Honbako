@testable import Sumi
import AidokuRunner
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiReaderDirectionConsistencyTests {
    @Test("The actual reader advances its filmstrip with a leftward drag in either source order and viewport")
    func readerAndScrubberAdvanceTogether() async throws {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var values = original
        values["General.incognitoMode"] = true
        values["Reader.liveText"] = false
        values["Reader.pagedPageLayout"] = "auto"
        defaults.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        for viewer in [Viewer.leftToRight, .rightToLeft] {
            for size in [CGSize(width: 420, height: 800), CGSize(width: 951, height: 669)] {
                let chapter = AidokuRunner.Chapter(key: "direction", chapterNumber: 1)
                let manga = AidokuRunner.Manga(sourceKey: "sumi-direction-test", key: "direction-\(viewer.rawValue)",
                    title: "Direction", viewer: viewer, chapters: [chapter])
                let reader = ReaderViewController(source: nil, manga: manga, chapter: chapter, startPage: 1)
                reader.sumiIsPreparingOpening = true
                let container = SumiDirectReaderController(content: UIViewController())
                let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                window.rootViewController = container; window.isHidden = false
                container.show(reader)
                defer { reader.sumiIsPreparingOpening = true; window.isHidden = true; window.rootViewController = nil }
                let paged = try #require(reader.reader as? ReaderPagedViewController)
                let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900)).image { context in
                    UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
                }
                paged.viewModel.sumiPageLoaderOverride = { selected in
                    (0..<8).map { Sumi.Page(sourceId: manga.sourceKey, chapterId: selected.id, index: $0, image: image) }
                }
                paged.setChapter(chapter, startPage: 1)
                let deadline = ContinuousClock.now.advanced(by: .seconds(6))
                while !paged.sumiReadyForOpening, ContinuousClock.now < deadline {
                    window.layoutIfNeeded(); reader.view.layoutIfNeeded(); paged.view.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(20))
                }
                #expect(paged.sumiReadyForOpening)
                reader.sumiDidOpenPreparedBook(); reader.showBars()
                window.layoutIfNeeded(); reader.view.layoutIfNeeded()
                let scrubber = try #require(descendants(window, type: SumiPageScrubber.self).first)
                let reversed = scrubber.isReversed
                #expect(!reversed, "The reader must not reverse its filmstrip when a source reports RTL")
                #expect(!scrubber.reversesThumbnailPages, "The previews preserve the real spread's printed order")
                let strip = try #require(descendants(scrubber, type: UICollectionView.self).first)
                scrubber.layoutIfNeeded(); strip.layoutIfNeeded()
                let flow = try #require(strip.collectionViewLayout as? SumiFilmstripLayout)
                let first = scrubber.accessibilityValue
                scrubber.scrollViewWillBeginDragging(strip)
                strip.contentOffset.x += flow.pitch
                scrubber.scrollViewDidScroll(strip)
                let next = size.width > size.height ? "Pages 3–4 of 8" : "Page 2 of 8"
                #expect(scrubber.accessibilityValue == next,
                    "A right-to-left finger drag must preview later pages, not stay on the first page")
                scrubber.cancelPreview()
                #expect(scrubber.accessibilityValue == first, "Canceling preserves the actual page")
                #expect(paged.sumiCurrentCanonicalPage == 1)
            }
        }
    }

    @Test("A full-reader scrub takes over an interrupted native turn without a late callback undoing its page")
    func scrubRecoversInterruptedNativeTurn() async throws {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var values = original
        values["General.incognitoMode"] = true
        values["Reader.liveText"] = false
        defaults.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        let chapter = AidokuRunner.Chapter(key: "interrupted", chapterNumber: 1)
        let manga = AidokuRunner.Manga(sourceKey: "sumi-direction-test", key: "interrupted",
            title: "Interrupted turn", viewer: .rightToLeft, chapters: [chapter])
        let reader = ReaderViewController(source: nil, manga: manga, chapter: chapter, startPage: 1)
        reader.sumiIsPreparingOpening = true
        let container = SumiDirectReaderController(content: UIViewController())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 420, height: 800))
        window.rootViewController = container; window.isHidden = false
        container.show(reader)
        defer { reader.sumiIsPreparingOpening = true; window.isHidden = true; window.rootViewController = nil }
        let paged = try #require(reader.reader as? ReaderPagedViewController)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
        }
        paged.viewModel.sumiPageLoaderOverride = { selected in
            (0..<8).map { Sumi.Page(sourceId: manga.sourceKey, chapterId: selected.id, index: $0, image: image) }
        }
        paged.setChapter(chapter, startPage: 1)
        let openingDeadline = ContinuousClock.now.advanced(by: .seconds(6))
        while !paged.sumiReadyForOpening, ContinuousClock.now < openingDeadline {
            window.layoutIfNeeded(); reader.view.layoutIfNeeded(); paged.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(paged.sumiReadyForOpening)
        reader.sumiDidOpenPreparedBook(); reader.showBars(); window.layoutIfNeeded()
        let originalPager = try #require(paged.children.compactMap { $0 as? UIPageViewController }.first)
        #expect(!(originalPager is SumiPageCurlViewController))
        let current = try #require(originalPager.viewControllers?.first)
        let next = try #require(paged.pageViewController(originalPager, viewControllerAfter: current))
        paged.pageViewController(originalPager, willTransitionTo: [next])
        reader.showBars()
        let scrubber = try #require(descendants(window, type: SumiPageScrubber.self).first)
        scrubber.accessibilityIncrement()
        let selectionDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while paged.sumiCurrentCanonicalPage != 2, ContinuousClock.now < selectionDeadline {
            window.layoutIfNeeded(); reader.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        let committed = paged.sumiCurrentCanonicalPage
        #expect(committed == 2, "An explicit scrub must recover from an interrupted native page turn")
        let replacement = try #require(paged.children.compactMap { $0 as? UIPageViewController }.first)
        let replaced = replacement !== originalPager
        #expect(replaced, "Discard the native pager's unfinished neighbor queue before selecting a page")
        paged.pageViewController(originalPager, didFinishAnimating: true,
            previousViewControllers: [current], transitionCompleted: false)
        let afterLateCallback = paged.sumiCurrentCanonicalPage
        #expect(afterLateCallback == 2, "The discarded pager cannot roll back the committed selection")
        scrubber.cancelPreview()
    }

    private func descendants<T: UIView>(_ view: UIView, type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type: type) }
    }
}
