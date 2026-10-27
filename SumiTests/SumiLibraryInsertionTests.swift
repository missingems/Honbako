@testable import Sumi
import Testing
import UIKit

@MainActor
struct SumiLibraryInsertionTests {
    @Test("A transferred cover lands in the current live library anchor without changing any library order")
    func resolvesLiveLibrarySlot() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let container = UIView(frame: CGRect(x: 20, y: 30, width: 400, height: 600))
        host.view.addSubview(container)
        let cover = UIView(frame: CGRect(x: 120, y: 200, width: 100, height: 150))
        container.addSubview(cover)
        let anchor = SumiBookSourceAnchor()
        anchor.view = cover
        let insertion = SumiLibraryInsertionState()
        insertion.register(anchor, for: "test:book")
        insertion.begin(bookID: "test:book")
        #expect(insertion.frame(in: container) == cover.frame)
        cover.frame.origin = CGPoint(x: 230, y: 320)
        #expect(insertion.frame(in: container) == cover.frame)
        #expect(insertion.frame(in: host.view) == container.convert(cover.frame, to: host.view))
        cover.removeFromSuperview()
        #expect(insertion.frame(in: container) == nil, "A detached lazy cell is never an animation destination")
        insertion.finish()
        #expect(insertion.bookID == nil)
        #expect(insertion.frame(in: container) == nil)
    }
}
