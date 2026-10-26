@testable import Sumi
import Testing
import UIKit

@MainActor
struct SumiReaderStatusBarTests {
    @Test("The full-screen reader lets its content reveal and hide the status bar")
    func contentOwnsStatusVisibility() {
        let content = SumiStatusBarTestContent()
        let host = SumiDirectReaderController(content: content)
        #expect(host.childForStatusBarHidden === content)
        #expect(host.childForStatusBarStyle === content)
        #expect(host.prefersStatusBarHidden)
        content.hidden = false
        #expect(!host.prefersStatusBarHidden)
        content.hidden = true
        #expect(host.prefersStatusBarHidden)
    }
}

@MainActor
private final class SumiStatusBarTestContent: UIViewController {
    var hidden = true
    override var prefersStatusBarHidden: Bool { hidden }
}
