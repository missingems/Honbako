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
    @Test("Identity resolution follows a replacement shelf cell while the old cell remains attached")
    func resolvesReplacementCell() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let old = UIView(frame: CGRect(x: 12, y: 30, width: 100, height: 150))
        let replacement = UIView(frame: CGRect(x: 170, y: 300, width: 100, height: 150))
        host.view.addSubview(old)
        host.view.addSubview(replacement)
        let firstAnchor = SumiBookSourceAnchor(); firstAnchor.view = old
        let secondAnchor = SumiBookSourceAnchor(); secondAnchor.view = replacement
        let registry = SumiLibraryInsertionState()
        registry.register(firstAnchor, for: "book")
        registry.register(secondAnchor, for: "book")
        #expect(registry.frame(for: "book", in: host.view) == replacement.frame)
        #expect(old.window != nil, "The old cell may still exist during a lazy-grid handoff")
        replacement.removeFromSuperview()
        #expect(registry.frame(for: "book", in: host.view) == nil, "Never fall back to the obsolete anchor")
    }

    @Test("Returning to a fully visible book leaves the actual library scroll offset unchanged")
    func visibleReturnNeverScrolls() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentSize = CGSize(width: 400, height: 1800)
        host.view.addSubview(scroll)
        let cover = UIView(frame: CGRect(x: 24, y: 440, width: 100, height: 150))
        scroll.addSubview(cover)
        scroll.contentOffset = CGPoint(x: 0, y: 300)
        let anchor = SumiBookSourceAnchor(); anchor.view = cover
        let registry = SumiLibraryInsertionState(); registry.register(anchor, for: "book")
        let offset = scroll.contentOffset
        #expect(registry.revealForReturn(bookID: "book") == .visible)
        #expect(scroll.contentOffset == offset)
        // Even a real order change needs no reveal if its new cell is visible.
        cover.frame.origin.y = 620
        #expect(registry.revealForReturn(bookID: "book") == .visible)
        #expect(scroll.contentOffset == offset)
    }

    @Test("A genuinely off-screen receiving book reveals only its clipped edge instead of centring the library")
    func offscreenReturnUsesMinimumReveal() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentSize = CGSize(width: 400, height: 1800)
        host.view.addSubview(scroll)
        let cover = UIView(frame: CGRect(x: 24, y: 800, width: 100, height: 150))
        scroll.addSubview(cover)
        scroll.contentOffset = CGPoint(x: 0, y: 300)
        let anchor = SumiBookSourceAnchor(); anchor.view = cover
        let registry = SumiLibraryInsertionState(); registry.register(anchor, for: "book")
        #expect(registry.revealForReturn(bookID: "book") == .revealed)
        #expect(abs(scroll.contentOffset.y - 350) < 1)
        #expect(scroll.contentOffset.x == 0)
        #expect(registry.revealForReturn(bookID: "book") == .visible)
    }

}
