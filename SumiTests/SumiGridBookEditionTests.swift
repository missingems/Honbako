@testable import Sumi
import Testing
import UIKit
import AidokuRunner

@MainActor
struct SumiGridBookEditionTests {
    @Test("Covers show an unlit placeholder synchronously while source artwork loads")
    func immediateColdPlaceholder() {
        let view = SumiGridBookView(frame: CGRect(x: 0, y: 0, width: 150, height: 200))
        view.configure(book: SumiBook(manga: AidokuRunner.Manga(sourceKey: "cold-placeholder",
            key: "book", title: "Visible cover")))
        #expect(view.image != nil && view.coverArtwork != nil)
        #expect(view.renderedBookPose == nil, "An early pickup must keep the visible flat edition")
    }

    @Test("A flat pickup stays unchanged when a legacy rendered edition arrives")
    func pinnedFlatEdition() {
        let view = SumiGridBookView(frame: CGRect(x: 0, y: 0, width: 150, height: 200))
        let print = artwork(.white)
        let physical = artwork(.black)
        view.applyFlatEdition(cover: print)
        #expect(view.renderedBookPose == nil)
        view.beginBookTransition()
        view.applyRenderedEdition(cover: print, rendered: physical)
        #expect(view.image === print && view.coverArtwork === print)
        #expect(view.renderedBookPose == nil)
        view.endBookTransition()
        #expect(view.image === print && view.renderedBookPose == nil)
    }

    @Test("Legacy rendered covers never reintroduce lighting or a physical tilt")
    func legacyRenderUsesUnmodifiedPrint() {
        let view = SumiGridBookView(frame: CGRect(x: 0, y: 0, width: 136, height: 200))
        let print = artwork(.white)
        view.applyRenderedEdition(cover: print, rendered: artwork(.black))
        #expect(view.image === print)
        #expect(view.coverArtwork === print)
        #expect(view.renderedBookPose == nil)
        #expect(view.accessibilityIdentifier == "Sumi.Grid.Cover")
    }

    @Test("A late cover cannot change the picked-up or newly returned book")
    func pinnedEdition() {
        let view = SumiGridBookView(frame: CGRect(x: 0, y: 0, width: 150, height: 200))
        let first = artwork(.white)
        let loaded = artwork(.black)
        view.applyRenderedEdition(cover: first, rendered: first)
        view.beginBookTransition()
        view.applyRenderedEdition(cover: loaded, rendered: loaded)
        #expect(view.image === first && view.coverArtwork === first)
        view.endBookTransition()
        #expect(view.image === first && view.coverArtwork === first,
                "Finishing the return must not reveal a brighter late-loaded edition")
        view.applyRenderedEdition(cover: loaded, rendered: loaded)
        #expect(view.image === first && view.coverArtwork === first)
    }

    @Test("Pending art updates atomically only after the returned tile leaves and reappears")
    func deferredRefreshAfterReturn() {
        let view = SumiGridBookView(frame: CGRect(x: 0, y: 0, width: 150, height: 200))
        let first = artwork(.white)
        let loaded = artwork(.black)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
        window.addSubview(view)
        view.applyRenderedEdition(cover: first, rendered: first)
        view.beginBookTransition()
        view.applyRenderedEdition(cover: loaded, rendered: loaded)
        // A full-screen reader can detach and reattach the grid during its
        // presentation. That lifecycle must not release the captured edition.
        view.removeFromSuperview()
        window.addSubview(view)
        view.endBookTransition()
        #expect(view.image === first && view.coverArtwork === first)
        view.removeFromSuperview()
        window.addSubview(view)
        #expect(view.image === loaded && view.coverArtwork === loaded)
    }

    private func artwork(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
    }
}
