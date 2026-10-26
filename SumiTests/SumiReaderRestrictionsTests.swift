@testable import Sumi
import AidokuRunner
import Testing
import UIKit
import VisionKit

@MainActor
@Suite(.serialized)
struct SumiReaderRestrictionsTests {
    @Test("Image load settings cannot re-enable pinch or double-tap zoom; Fill keeps vertical reading")
    func zoomRemainsLocked() {
        let scroll = ZoomableScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let content = UIView(frame: scroll.bounds)
        scroll.addSubview(content)
        scroll.zoomView = content
        scroll.pageContentFrame = { CGRect(x: 100, y: 0, width: 200, height: 800) }
        scroll.zoomEnabled = true
        scroll.doubleTapEnabled = true
        scroll.applyPageSizing(.fit, resetZoom: true)
        #expect(scroll.pinchGestureRecognizer?.isEnabled != true)
        #expect(!scroll.doubleTapEnabled)
        #expect(!scroll.bouncesZoom)
        #expect(scroll.minimumZoomScale == scroll.maximumZoomScale)
        scroll.zoom(to: CGPoint(x: 200, y: 400), animated: false)
        #expect(scroll.zoomScale == 1)

        scroll.applyPageSizing(.fill, resetZoom: true)
        #expect(scroll.isScrollEnabled)
        #expect(scroll.panGestureRecognizer.isEnabled)
        #expect(scroll.alwaysBounceVertical)
        #expect(scroll.minimumZoomScale == scroll.maximumZoomScale)
        #expect(!scroll.permitsPagePan(velocity: CGPoint(x: 100, y: 0)))
        #expect(scroll.permitsPagePan(velocity: CGPoint(x: 0, y: 100)))
        scroll.zoomEnabled = false
        scroll.zoomEnabled = true
        scroll.doubleTapEnabled = true
        #expect(scroll.pinchGestureRecognizer?.isEnabled != true)
        #expect(!scroll.doubleTapEnabled)
    }

    @Test("Persisted text and dictionary preferences cannot add page hold actions")
    func pageHoldActionsStayDisabled() async throws {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var overrides = original
        overrides["General.incognitoMode"] = true
        overrides["Reader.liveText"] = true
        overrides[AppSettings.dictionary.enable.key] = true
        overrides[AppSettings.dictionary.lookupGesture.key] = "longPress"
        overrides[AppSettings.dictionary.textOverlayMode.key] = true
        defaults.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }

        let chapter = AidokuRunner.Chapter(key: "restrictions")
        let manga = AidokuRunner.Manga(sourceKey: "sumi-restrictions-test", key: "book", title: "Restricted reader")
        let reader = ReaderViewController(source: nil, manga: manga, chapter: chapter, startPage: 1)
        reader.sumiIsPreparingOpening = true
        reader.loadViewIfNeeded()
        #expect(!(reader.view.gestureRecognizers ?? []).contains { $0 is UILongPressGestureRecognizer })
        let paged = try #require(reader.reader as? ReaderPagedViewController)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
        }
        paged.viewModel.pages = (0..<2).map {
            .init(sourceId: manga.sourceKey, chapterId: chapter.id, index: $0, image: image)
        }
        paged.loadPageControllers(chapter: chapter)
        paged.loadPages(in: 1...2)
        for page in paged.pageViewControllers where page.pageView != nil {
            let imageView = try #require(page.pageView?.imageView)
            #expect(!imageView.interactions.contains { $0 is UIContextMenuInteraction || $0 is ImageAnalysisInteraction })
            #expect(!(imageView.gestureRecognizers ?? []).contains { $0 is UILongPressGestureRecognizer })
        }
        let first = try #require(paged.pageViewControllers.first { $0.pageView != nil })
        let wide = ReaderBookWideLeafViewController(canonicalController: first, side: .left)
        wide.loadViewIfNeeded()
        #expect(!wide.imageView.interactions.contains { $0 is UIContextMenuInteraction || $0 is ImageAnalysisInteraction })
        #expect(!(wide.imageView.gestureRecognizers ?? []).contains { $0 is UILongPressGestureRecognizer })
    }
}
