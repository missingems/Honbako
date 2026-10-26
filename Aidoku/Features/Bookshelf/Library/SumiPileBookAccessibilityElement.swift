#if SUMI
import UIKit

final class SumiPileBookAccessibilityElement: UIAccessibilityElement {
    weak var pileView: SumiBookPileView?
    let bookID: String

    init(view: SumiBookPileView, bookID: String) {
        pileView = view
        self.bookID = bookID
        super.init(accessibilityContainer: view)
        accessibilityTraits = .button
        accessibilityIdentifier = "Sumi.Library.Book.\(bookID)"
        accessibilityHint = "Open book"
    }

    override func accessibilityActivate() -> Bool {
        pileView?.openBook(withID: bookID) ?? false
    }
}
#endif
