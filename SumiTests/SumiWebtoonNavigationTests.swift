@testable import Sumi
import AidokuRunner
import AsyncDisplayKit
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SumiWebtoonNavigationTests {
    @Test("Continuous sources use real vertical scrolling and stay nonzoomable")
    func scrollNavigation() async throws {
        let store = ReaderTemporaryPageStore()
        let reader = ReaderWebtoonViewController(source: nil,
            manga: .init(sourceKey: "sumi-scroll-test", key: "book", title: "Tall pages"), temporaryPageStore: store)
        reader.readingMode = .webtoon
        let chapter = AidokuRunner.Chapter(key: "scroll-chapter")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 1000)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 1000))
            UIColor.black.setFill()
            context.fill(CGRect(x: 30, y: 30, width: 340, height: 940))
        }
        reader.viewModel.sumiPageLoaderOverride = { chapter in
            (0..<4).map { .init(sourceId: "sumi-scroll-test", chapterId: chapter.id, index: $0, image: image) }
        }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        host.add(child: reader)
        reader.view.frame = CGRect(x: 0, y: 0, width: 450, height: 800)
        reader.view.autoresizingMask = []
        defer {
            window.isHidden = true
            window.rootViewController = nil
            Task { await store.removeAll() }
        }
        reader.setChapter(chapter, startPage: 1)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !reader.sumiReadyForOpening, ContinuousClock.now < deadline {
            window.layoutIfNeeded()
            reader.view.setNeedsLayout()
            reader.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(reader.sumiReadyForOpening)
        #expect(reader.scrollView.maximumZoomScale == 1)
        #expect(reader.scrollView.pinchGestureRecognizer?.isEnabled != true)
        #expect(!reader.zoomView.doubleTapEnabled)
        #expect(reader.scrollView === reader.collectionNode.view)
        #expect(reader.zoomView.scrollNode.isHidden)
        #expect(!reader.zoomView.scrollNode.isUserInteractionEnabled)
        #expect(reader.zoomView.scrollNode.view.delegate == nil)
        #expect(reader.scrollView.isScrollEnabled)
        #expect(reader.scrollView.panGestureRecognizer.isEnabled)
        #expect(reader.scrollView.contentSize.height > reader.scrollView.bounds.height)
        var hit = reader.view.hitTest(CGPoint(x: reader.view.bounds.width * 0.45,
                                             y: reader.view.bounds.height * 0.8), with: nil)
        var reachesScrollView = false
        var hitPath: [String] = []
        while let candidate = hit {
            hitPath.append(String(describing: type(of: candidate)))
            if candidate === reader.scrollView { reachesScrollView = true }
            hit = candidate.superview
        }
        #expect(reachesScrollView, "Touches must reach the scrolling surface: \(hitPath)")
        let firstOffset = reader.scrollView.contentOffset.y
        reader.sumiMove(toCanonicalPage: 3)
        #expect(reader.scrollView.contentOffset.y > firstOffset)
        #expect(reader.sumiIsCanonicalPageVisible(3))
        var began = 0
        reader.sumiOnPageTurnBegan = { began += 1 }
        #expect(await reader.sumiAnimate(toCanonicalPage: 4))
        #expect(began == 1)
        #expect(reader.sumiIsCanonicalPageVisible(4))
        #expect(reader.sumiCurrentCanonicalPage == 4)
    }
}
