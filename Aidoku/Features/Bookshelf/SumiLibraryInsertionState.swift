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
        guard let bookID, let view = anchors[bookID]?.view, view.window != nil else { return nil }
        let frame = view.convert(view.bounds, to: container)
        guard frame.width > 1, frame.height > 1, frame.intersects(container.bounds) else { return nil }
        return frame
    }

    func finish() { bookID = nil }
}
#endif
