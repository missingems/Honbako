@testable import Sumi
import AidokuRunner
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiReaderEmbeddingTests {
    @Test("The full reader uses full-bleed actual pages and saves progress only after opening")
    func fullReaderWideOpening() async throws {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var overrides = original
        overrides["General.incognitoMode"] = true
        overrides["Reader.liveText"] = false
        overrides["Reader.readingMode"] = "auto"
        overrides["Reader.pageSizing"] = "fill" // Existing installs must migrate to the fit-only reader.
        defaults.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
        let chapter = AidokuRunner.Chapter(key: "embedding", chapterNumber: 1)
        var manga = AidokuRunner.Manga(sourceKey: "sumi-embedding-test", key: "book", title: "Embedded book")
        manga.viewer = .leftToRight
        manga.chapters = [chapter]
        let reader = ReaderViewController(source: nil, manga: manga, chapter: chapter, startPage: 1)
        reader.sumiIsPreparingOpening = true
        let container = SumiDirectReaderController(content: UIViewController())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 951, height: 669))
        window.rootViewController = container
        window.isHidden = false
        container.show(reader)
        let paged = reader.reader as? ReaderPagedViewController
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
        }
        paged?.viewModel.sumiPageLoaderOverride = { selected in
            (0..<6).map { Sumi.Page(sourceId: manga.sourceKey, chapterId: selected.id, index: $0, image: image) }
        }
        var failure: Error?
        do {
            let paged = try #require(paged)
            for _ in 0..<8 {
                window.setNeedsLayout(); window.layoutIfNeeded()
                reader.view.setNeedsLayout(); reader.view.layoutIfNeeded()
                paged.view.setNeedsLayout(); paged.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(30))
            }
            #expect(reader.view.bounds.width > reader.view.bounds.height)
            #expect(paged.view.frame == reader.view.bounds)
            let pager = try #require(paged.children.compactMap { $0 as? UIPageViewController }.first)
            #expect(pager.view.frame == SumiReaderPresentation.contentFrame(
                in: paged.view.bounds, safeAreaInsets: window.safeAreaInsets))
            #expect(pager.view.frame == paged.view.bounds)
            let spread = try #require(pager.viewControllers?.first as? ReaderBookSpreadViewController)
            #expect(spread.leaves[0] === paged.pageViewControllers[1])
            #expect(spread.leaves[1] === paged.pageViewControllers[2])
            #expect(paged.visibleActualPageRange(in: spread) == 1...2)
            #expect(!spread.leaves.contains { $0 is SumiIndexLeafViewController })
            #expect(reader.navigationController === container)
            #expect(container.children.first === reader)
            #expect(paged.sumiReadyForOpening)
            #expect(paged.sumiEffectivePageSizing == .fit)
            for case let leaf as ReaderPageViewController in spread.leaves {
                #expect(leaf.zoomView?.effectivePageSizing == .fit)
                #expect(leaf.zoomView?.zoomScale == 1)
            }
            // Preparing an embedded book may load and lay out its real pages,
            // but leaving that loading state must not schedule a history save.
            reader.viewWillDisappear(false)
            #expect(reader.sumiIsPreparingOpening)
            #expect(reader.sumiPendingHistorySave == nil)
            reader.sumiDidOpenPreparedBook()
            #expect(!reader.sumiIsPreparingOpening)
            reader.sumiDidOpenPreparedBook() // The opening completion is idempotent.
            reader.viewWillDisappear(false)
            #expect(reader.sumiPendingHistorySave != nil)
            await reader.sumiPendingHistorySave?.value
        } catch { failure = error }
        window.isHidden = true
        window.rootViewController = nil
        await reader.sumiPendingHistorySave?.value
        defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain)
        if let failure { throw failure }
    }
}
