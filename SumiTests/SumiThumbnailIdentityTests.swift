@testable import Sumi
import Testing
import UIKit

@MainActor
struct SumiThumbnailIdentityTests {
    @Test("A delayed spread uses placeholders for its requested pages instead of showing the previous spread")
    func loadingSpreadNeverShowsStaleArtwork() async throws {
        func image(_ color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
            }
        }
        let view = SumiSpreadThumbnailView(frame: CGRect(x: 0, y: 0, width: 140, height: 100))
        let red = image(.red), blue = image(.blue), green = image(.green), purple = image(.purple)
        view.configure(identity: "chapter", pages: [1, 2], reversed: false,
                       preservingCurrent: true, provider: { $0 == 1 ? red : blue })
        for _ in 0..<100 where view.displayedPages != [1, 2] { await Task.yield() }
        #expect(view.displayedPages == [1, 2])
        var secondLeaf: CheckedContinuation<UIImage?, Never>?
        view.configure(identity: "chapter", pages: [3, 4], reversed: false, preservingCurrent: true, provider: { page in
            if page == 3 { return green }
            return await withCheckedContinuation { secondLeaf = $0 }
        })
        view.layoutIfNeeded()
        let images = view.subviews.compactMap { $0 as? UIImageView }
        let placeholder = try #require(view.subviews.first { $0.accessibilityIdentifier == "Sumi.Reader.PreviewPlaceholder.4" })
        for _ in 0..<100 where secondLeaf == nil || images.first?.image !== green { await Task.yield() }
        #expect(secondLeaf != nil)
        #expect(view.displayedPages.isEmpty)
        #expect(images.first?.image === green)
        #expect(images.last?.image == nil)
        #expect(!placeholder.isHidden, "The loading half must represent page 4, never old page 2")
        #expect(view.accessibilityValue == "Loading preview")
        secondLeaf?.resume(returning: purple)
        for _ in 0..<100 where view.displayedPages != [3, 4] { await Task.yield() }
        #expect(view.displayedPages == [3, 4])
        #expect(images.first?.image === green)
        #expect(images.last?.image === purple)
        #expect(placeholder.isHidden)
        var failed = false
        view.configure(identity: "chapter", pages: [5, 6], reversed: false, preservingCurrent: true,
                       provider: { $0 == 5 ? red : nil }, ready: { failed = !$0 })
        for _ in 0..<100 where !failed { await Task.yield() }
        #expect(failed)
        #expect(images.first?.image === red)
        #expect(images.last?.image == nil, "Failure must not leave a different page beneath the requested page number")
        #expect(view.displayedPages.isEmpty)
    }

    @Test("A delayed preview from an old chapter cannot replace the current chapter at the same page number")
    func obsoleteChapterPreview() async throws {
        func image(_ color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
            }
        }
        let view = SumiSpreadThumbnailView(frame: CGRect(x: 0, y: 0, width: 70, height: 100))
        var old: CheckedContinuation<UIImage?, Never>?
        view.configure(identity: "old", pages: [1], reversed: false, preservingCurrent: true,
                       provider: { _ in await withCheckedContinuation { old = $0 } })
        for _ in 0..<100 where old == nil { await Task.yield() }
        let blue = image(.blue)
        view.configure(identity: "new", pages: [1], reversed: false, preservingCurrent: true, provider: { _ in blue })
        #expect(view.displayedPages.isEmpty)
        for _ in 0..<100 where view.displayedPages != [1] { await Task.yield() }
        let views = view.subviews.compactMap { $0 as? UIImageView }
        #expect(views.first?.image === blue)
        old?.resume(returning: image(.red))
        for _ in 0..<10 { await Task.yield() }
        #expect(views.first?.image === blue)
    }

    @Test("Pages with the source's default zero index still keep distinct preview images")
    func distinctCanonicalPreviews() async throws {
        func image(_ color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 80, height: 120)).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
            }
        }
        let first = Sumi.Page(sourceId: "source", chapterId: "chapter", image: image(.red))
        let second = Sumi.Page(sourceId: "source", chapterId: "chapter", image: image(.blue))
        #expect(first.index == second.index)
        let loader = SumiPageThumbnailLoader(mangaKey: "book")
        let a = try #require(await loader.image(for: first, position: 1, source: nil))
        let b = try #require(await loader.image(for: second, position: 2, source: nil))
        #expect(a.pngData() != b.pngData(), "A chapter's pages must never share one cached thumbnail")
        let again = try #require(await loader.image(for: first, position: 1, source: nil))
        #expect(a.pngData() == again.pngData())
        let shifted = try #require(await loader.image(for: first, position: 2, source: nil))
        #expect(shifted.pngData() == a.pngData(),
                "Inserting a split leaf must not reuse the different artwork previously cached at this display position")
    }
}
