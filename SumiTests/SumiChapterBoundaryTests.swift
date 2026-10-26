@testable import Sumi
import AidokuRunner
import Testing
import UIKit

@MainActor
struct SumiChapterBoundaryTests {
    @Test("Chapter boundaries show a quiet end without naming or linking an adjacent chapter")
    func nextAndEndStates() {
        let view = SumiChapterBoundaryView()
        var continued = false
        view.onContinue = { continued = true }
        view.update(type: .next, destination: .init(key: "second", chapterNumber: 2))
        #expect(view.titleLabel.text == "Chapter End")
        #expect(view.detailLabel.text == nil && view.detailLabel.isHidden)
        #expect(view.continueButton.isHidden)
        view.continueButton.sendActions(for: .touchUpInside)
        #expect(!continued, "An old chapter-link action must not survive on the quiet boundary")
        view.update(type: .next, destination: nil)
        #expect(view.titleLabel.text == "Chapter End")
        #expect(view.continueButton.isHidden)
        #expect(view.detailLabel.text == nil)
        view.update(type: .previous, destination: .init(key: "first", chapterNumber: 1))
        #expect(view.titleLabel.text == "Chapter End")
        #expect(view.detailLabel.text == nil && view.continueButton.isHidden)
        view.update(type: .previous, destination: nil)
        #expect(view.titleLabel.text == "The Beginning")
    }

    @Test("A failed chapter keeps retry available without leaking it into the normal page boundary")
    func failureCanRetryThenReturnToQuietEnd() {
        let view = SumiChapterBoundaryView()
        var retries = 0
        view.showError { retries += 1 }
        #expect(view.titleLabel.text == "Chapter Unavailable")
        #expect(!view.continueButton.isHidden)
        #expect(view.continueButton.configuration?.title == "Try Again")
        view.continueButton.sendActions(for: .touchUpInside)
        #expect(retries == 1)
        view.update(type: .next, destination: .init(key: "second", chapterNumber: 2))
        #expect(view.titleLabel.text == "Chapter End")
        #expect(view.detailLabel.isHidden && view.continueButton.isHidden)
        view.continueButton.sendActions(for: .touchUpInside)
        #expect(retries == 1)
    }
}
