@testable import Sumi
import AsyncDisplayKit
import Foundation
import Nuke
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct HonbakoPageFailurePresentationTests {
    @Test("Loading, failure and retry have one exclusive presentation")
    func exclusivePageStatus() throws {
        let status = SumiPageImageLoadingView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        #expect(status.state == .loading)
        #expect(descendants(status).compactMap { $0 as? UIActivityIndicatorView }.contains { $0.isAnimating })
        var retries = 0
        status.showFailure { retries += 1 }
        status.layoutIfNeeded()
        let retry = try #require(descendants(status).compactMap { $0 as? UIButton }.first)
        #expect(status.state == .failed)
        #expect(descendants(status).compactMap { $0 as? UIActivityIndicatorView }.allSatisfy { !$0.isAnimating })
        #expect(!retry.isHidden && retry.bounds.height >= 44)
        #expect(!descendants(status).compactMap { $0 as? UILabel }.contains { !$0.isHidden && $0.text == "Loading page" })
        #expect(status.hitTest(retry.convert(CGPoint(x: retry.bounds.midX, y: retry.bounds.midY), to: status), with: nil) === retry)
        #expect(status.hitTest(CGPoint(x: 2, y: 2), with: nil) == nil)
        retry.sendActions(for: .touchUpInside)
        #expect(retries == 1)
        #expect(status.state == .loading)
        #expect(retry.isHidden)
        retry.sendActions(for: .touchUpInside)
        #expect(retries == 1, "A retry action can be started only once before a new failure")
    }

    @Test("A tall scrolling page keeps loading and retry controls inside its landscape viewport")
    func tallPageStatusUsesVisibleViewport() throws {
        let paper = CGRect(x: 0, y: 0, width: 678, height: 973)
        let status = SumiPageImageLoadingView(frame: paper)
        let firstViewport = CGRect(x: 0, y: 0, width: 678, height: 466)
        status.updateContentViewport(firstViewport)
        status.layoutIfNeeded()
        let loading = try #require(descendants(status).compactMap { $0 as? UILabel }.first { $0.text == "Loading page" })
        #expect(firstViewport.contains(loading.convert(loading.bounds, to: status)))
        status.showFailure {}
        status.layoutIfNeeded()
        let retry = try #require(descendants(status).compactMap { $0 as? UIButton }.first)
        #expect(firstViewport.insetBy(dx: 0, dy: 24).contains(retry.convert(retry.bounds, to: status)))
        #expect(retry.bounds.height >= 44)
        #expect(status.hitTest(retry.convert(CGPoint(x: retry.bounds.midX, y: retry.bounds.midY), to: status), with: nil) === retry)
        let scrolledViewport = firstViewport.offsetBy(dx: 0, dy: 400)
        status.updateContentViewport(scrolledViewport)
        status.layoutIfNeeded()
        #expect(scrolledViewport.insetBy(dx: 0, dy: 24).contains(retry.convert(retry.bounds, to: status)))
        #expect(status.frame == paper, "Only the status controls move; the page and its scroll geometry stay intact")
        #expect(status.hitTest(CGPoint(x: 2, y: 450), with: nil) == nil)
    }

    @Test("A late reveal completion cannot replace a newer failure")
    func failedStateInvalidatesReveal() async throws {
        let status = SumiPageImageLoadingView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        let imageView = UIImageView(image: image())
        status.reveal(imageView, animated: true)
        status.showFailure {}
        try await Task.sleep(for: .milliseconds(300))
        #expect(status.state == .failed)
        #expect(!status.isHidden)
        #expect(!status.isRevealing)
    }

    @Test("A failed page stops loading and a retry restores the same canonical page")
    func pagedFileFailureAndRetry() async throws {
        let fixture = try makeMissingPage()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = ReaderTemporaryPageStore()
        let controller = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: store)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        controller.view.layoutIfNeeded()
        controller.setPage(fixture.page)
        try await wait { controller.sumiImageLoadFailed }
        let page = try #require(controller.pageView)
        let status = try #require(page.subviews.compactMap { $0 as? SumiPageImageLoadingView }.first)
        #expect(status.state == .failed)
        #expect(page.progressView.isHidden)
        #expect(!descendants(controller.view).compactMap { $0 as? UIButton }.contains {
            !$0.isHidden && $0.currentTitle == NSLocalizedString("RELOAD")
        })
        try image().pngData()!.write(to: fixture.url)
        controller.reload()
        try await wait { page.imageView.image != nil }
        #expect(!controller.sumiImageLoadFailed)
        #expect(controller.page?.key == fixture.page.key)
        #expect(controller.page?.index == 3)
        #expect(status.state == .hidden)
        await store.removeAll()
    }

    @Test("A canceled page request is never presented as a connection failure")
    func canceledLoadIsNotFailure() async throws {
        let fixture = try makeMissingPage()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = ReaderTemporaryPageStore()
        let page = ReaderPageView(temporaryPageStore: store)
        let load = Task { await page.setPage(fixture.page) }
        load.cancel()
        #expect(await load.value == false)
        #expect(!page.sumiImageLoadFailed)
        #expect(!page.subviews.contains { $0.accessibilityIdentifier == "Sumi.Reader.Page.Error" })
        await store.removeAll()
    }

    @Test("Cancellation recognition preserves real transport and decoding failures")
    func cancellationClassification() {
        #expect(SumiPageImageLoadCancellation.contains(CancellationError()))
        #expect(SumiPageImageLoadCancellation.contains(URLError(.cancelled)))
        #expect(SumiPageImageLoadCancellation.contains(ImagePipeline.Error.cancelled))
        #expect(SumiPageImageLoadCancellation.contains(ImagePipeline.Error.dataLoadingFailed(error: URLError(.cancelled))))
        #expect(!SumiPageImageLoadCancellation.contains(URLError(.notConnectedToInternet)))
        #expect(!SumiPageImageLoadCancellation.contains(ImagePipeline.Error.dataIsEmpty))
    }

    @Test("Webtoon failure stays terminal until the reader explicitly retries")
    func webtoonFileFailureAndRetry() async throws {
        let fixture = try makeMissingPage()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = ReaderTemporaryPageStore()
        let node = ReaderWebtoonPageNode(source: nil, page: fixture.page,
            temporaryPageStore: store, pillarboxLayoutState: ReaderPillarboxLayoutState())
        await node.loadPage()
        #expect(node.sumiImageLoadFailed)
        #expect(node.image == nil)
        try image().pngData()!.write(to: fixture.url)
        node.displayPage()
        await Task.yield()
        #expect(node.image == nil, "Layout/visibility callbacks must not silently start an endless retry loop")
        #expect(await node.reloadCurrentImage())
        #expect(!node.sumiImageLoadFailed)
        #expect(node.image != nil)
        #expect(node.page.key == fixture.page.key)
        await store.removeAll()
    }

    @Test("Wide leaves show a tappable retry instead of a perpetual loading surface")
    func wideLeafMirrorsFailureAndRetry() async throws {
        let fixture = try makeMissingPage()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = ReaderTemporaryPageStore()
        let controller = ReaderPageViewController(type: .page, delegate: nil, temporaryPageStore: store)
        controller.setPage(fixture.page)
        try await wait { controller.sumiImageLoadFailed }
        let leaf = ReaderBookWideLeafViewController(canonicalController: controller, side: .left)
        leaf.loadViewIfNeeded()
        leaf.view.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        leaf.refreshImage()
        leaf.view.layoutIfNeeded()
        let status = try #require(leaf.view.subviews.compactMap { $0 as? SumiPageImageLoadingView }.first)
        let retry = try #require(descendants(status).compactMap { $0 as? UIButton }.first)
        #expect(leaf.sumiImageLoadFailed)
        #expect(status.state == .failed)
        let point = retry.convert(CGPoint(x: retry.bounds.midX, y: retry.bounds.midY), to: leaf.view)
        #expect(leaf.view.hitTest(point, with: nil) === retry)
        try image().pngData()!.write(to: fixture.url)
        retry.sendActions(for: .touchUpInside)
        try await wait { controller.pageView?.imageView.image != nil }
        leaf.refreshImage()
        #expect(!leaf.sumiImageLoadFailed)
        #expect(leaf.imageView.image != nil)
        await store.removeAll()
    }

    private func makeMissingPage() throws -> (page: Sumi.Page, url: URL, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("page.png")
        return (Sumi.Page(sourceId: "page-failure-fixture", chapterId: "chapter", index: 3, imageURL: url.absoluteString), url, directory)
    }

    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        }
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(condition())
    }
}
