@testable import Sumi
import Foundation
import Testing

@MainActor
struct SumiSearchPresentationTests {
    @Test("Opening a book suspends automatic keyboard focus until Search is deliberately revealed again")
    func keyboardStaysResignedAfterReading() {
        let search = SumiSearchPresentation()
        search.reveal()
        search.suspendKeyboard()
        #expect(search.isPresented)
        #expect(!search.requestsKeyboard)
        search.dismiss()
        search.reveal()
        #expect(search.requestsKeyboard)
    }

    @Test("Search starts hidden and a pull previews it without committing focus")
    func interactivePull() {
        let presentation = SumiSearchPresentation()
        #expect(!presentation.isPresented)
        #expect(presentation.revealProgress == 0)

        presentation.updatePull(distance: 13)
        let first = presentation.revealProgress
        #expect(first > 0 && first < 1)
        #expect(!presentation.isPresented)

        presentation.updatePull(distance: 39)
        let further = presentation.revealProgress
        #expect(further > first && further < 1)
        #expect(!presentation.isPresented)

        presentation.updatePull(distance: 13)
        #expect(presentation.revealProgress == first,
                "Reversing the finger must reverse the reveal rather than accumulate distance")
        #expect(!presentation.isPresented)
    }

    @Test("Pulling back or canceling removes the preview without opening search")
    func canceledPull() {
        let presentation = SumiSearchPresentation()
        presentation.updatePull(distance: 26)
        presentation.updatePull(distance: -12)
        #expect(presentation.revealProgress == 0)
        #expect(!presentation.isPresented)

        presentation.updatePull(distance: 26)
        presentation.finishPull()
        #expect(presentation.revealProgress == 0)
        #expect(presentation.pullProgress == 0)
        #expect(!presentation.isPresented)
    }

    @Test("Overscroll stays fully revealed until the finger commits or retreats")
    func clampedPull() {
        let presentation = SumiSearchPresentation()
        presentation.updatePull(distance: 1_000)
        #expect(presentation.revealProgress == 1)
        #expect(!presentation.isPresented,
                "A long held pull must not steal the grid's active pan or show the keyboard")
        presentation.updatePull(distance: 26)
        #expect(presentation.revealProgress > 0 && presentation.revealProgress < 1)
        presentation.finishPull()
        #expect(presentation.revealProgress == 0)
    }

    @Test("Committing hands the preview to focused search and ignores stale scroll updates")
    func committedRevealAndDismissal() {
        let presentation = SumiSearchPresentation()
        presentation.updatePull(distance: 26)
        presentation.reveal()
        #expect(presentation.isPresented)
        #expect(presentation.revealProgress == 1)
        #expect(presentation.pullProgress == 0)

        presentation.updatePull(distance: 26)
        #expect(presentation.pullProgress == 0)
        presentation.finishPull()
        #expect(presentation.isPresented)
        #expect(presentation.revealProgress == 1,
                "The grid settling must not fade out an already committed search")

        presentation.dismiss()
        #expect(!presentation.isPresented)
        #expect(presentation.revealProgress == 0)
        #expect(presentation.pullProgress == 0)
        presentation.updatePull(distance: 26)
        #expect(presentation.revealProgress > 0 && presentation.revealProgress < 1)
        #expect(!presentation.isPresented)
    }
}
