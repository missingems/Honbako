@testable import Sumi
import Testing
import UIKit

@MainActor
struct SumiReaderInteractionTests {
    @Test("Spreads keep canonical source pages together, including an isolated wide image")
    func sourceSpreads() {
        let model = SumiScrubberPages(total: 5, spreads: [[1, 2], [3], [4, 5]])
        #expect(model.groups == [[1, 2], [3], [4, 5]])
        #expect(model.index(containing: 2) == 0)
        #expect(model.label(for: 0) == "Pages 1–2 of 5")
        #expect(model.label(for: 1) == "Page 3 of 5")
    }

    @Test("A paired scrubber steps by visible spreads and cancellation preserves the exact second page")
    func spreadCommitAndCancel() {
        let bar = SumiPageScrubber(frame: CGRect(x: 0, y: 0, width: 400, height: 64))
        var commits: [Int] = []
        bar.onCommit = { commits.append($0) }
        bar.update(chapterKey: "one", totalPages: 5, currentPage: 2, spreads: [[1, 2], [3, 4], [5]])
        #expect(bar.accessibilityValue == "Pages 1–2 of 5")
        bar.preview(at: CGPoint(x: 15, y: 20)); bar.finishPreview(commit: true)
        #expect(commits.isEmpty, "Landing on the current spread must not reset its exact second-page focus")
        bar.preview(at: CGPoint(x: 390, y: 20))
        #expect(bar.accessibilityValue == "Page 5 of 5")
        bar.finishPreview(commit: false)
        #expect(commits.isEmpty)
        #expect(bar.accessibilityValue == "Pages 1–2 of 5")
        bar.preview(at: CGPoint(x: 200, y: 20)); bar.finishPreview(commit: true)
        #expect(commits == [3])
        #expect(bar.accessibilityValue == "Pages 3–4 of 5")
        bar.accessibilityIncrement()
        #expect(commits == [3, 5])
        bar.isReversed = true
        bar.preview(at: CGPoint(x: 390, y: 20)); bar.finishPreview(commit: true)
        #expect(commits.last == 1)
    }

    @Test("Short deliberate turns and flicks finish; small nudges and reversed drags cancel")
    func turnIntent() {
        #expect(SumiPageTurnIntent.shouldComplete(progress: 0.15, velocity: 0, distance: 450))
        #expect(SumiPageTurnIntent.shouldComplete(progress: 0.08, velocity: 0, distance: 900))
        #expect(SumiPageTurnIntent.shouldComplete(progress: 0.30, velocity: 0, distance: 450))
        #expect(SumiPageTurnIntent.shouldComplete(progress: 0.08, velocity: 280, distance: 450))
        #expect(!SumiPageTurnIntent.shouldComplete(progress: 0.05, velocity: 800, distance: 100))
        #expect(!SumiPageTurnIntent.shouldComplete(progress: 0.10, velocity: 0, distance: 450))
        #expect(!SumiPageTurnIntent.shouldComplete(progress: 0.55, velocity: -200, distance: 450))
        #expect(!SumiPageTurnIntent.shouldComplete(progress: 0.25, velocity: 0, distance: 900, translation: 24))
        #expect(SumiPageTurnIntent.shouldComplete(progress: 0.25, velocity: 0, distance: 900, translation: 68))
    }
}
