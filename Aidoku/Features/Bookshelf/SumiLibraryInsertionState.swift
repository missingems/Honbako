#if SUMI
import Combine
import UIKit

/// Connects a saved search cover to its real, stable library slot. Anchors do
/// not retain their native views, so off-screen grid cells remain disposable.
@MainActor
final class SumiLibraryInsertionState: ObservableObject {
    @Published private(set) var bookID: String?
    @Published private(set) var scrollRequest = 0
    private var anchors: [String: SumiBookSourceAnchor] = [:]

    func register(_ anchor: SumiBookSourceAnchor, for bookID: String) {
        anchors[bookID] = anchor
    }

    func begin(bookID: String) {
        self.bookID = bookID
        requestScroll()
    }

    func requestScroll() { scrollRequest &+= 1 }

    func frame(in container: UIView) -> CGRect? {
        guard let bookID else { return nil }
        return frame(for: bookID, in: container)
    }

    func frame(for bookID: String, in container: UIView) -> CGRect? {
        guard let view = anchors[bookID]?.view, view.window != nil else { return nil }
        let frame = view.convert(view.bounds, to: container)
        guard frame.width > 1, frame.height > 1, frame.intersects(container.bounds) else { return nil }
        return frame
    }

    enum ReturnReveal: Equatable { case visible, revealed, unavailable }

    /// Keep an already visible destination exactly where the reader left it.
    /// UIKit reveals a materialised off-screen cell by the smallest displacement.
    @discardableResult
    func revealForReturn(bookID: String) -> ReturnReveal {
        guard let view = anchors[bookID]?.view, view.window != nil else { return .unavailable }
        var ancestor = view.superview
        while let candidate = ancestor {
            if let scroll = candidate as? UIScrollView {
                let rect = view.convert(view.bounds, to: scroll)
                let viewport = scroll.bounds.inset(by: scroll.adjustedContentInset)
                guard rect.width > 1, rect.height > 1 else { return .unavailable }
                if viewport.insetBy(dx: -0.5, dy: -0.5).contains(rect) { return .visible }
                scroll.scrollRectToVisible(rect, animated: false)
                scroll.layoutIfNeeded()
                return .revealed
            }
            ancestor = candidate.superview
        }
        return .visible
    }

    func finish() { bookID = nil }
}
#endif
