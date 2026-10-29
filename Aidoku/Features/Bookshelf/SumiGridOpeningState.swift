#if SUMI
import Combine

@MainActor
final class SumiGridOpeningState: ObservableObject {
    @Published var bookID: String?
    @Published var returningBookID: String?
    @Published var returnRequest = 0
    private(set) var returnLayoutComplete = false
    private(set) var isPreparingReturn = false

    func beginReturnPreparation() {
        isPreparingReturn = true
        returnLayoutComplete = false
    }

    func finishReturnPreparation() {
        isPreparingReturn = false
        returningBookID = nil
    }

    func prepareReturn(to bookID: String) {
        returningBookID = bookID
        returnLayoutComplete = false
        returnRequest &+= 1
    }

    func finishReturnLayout(request: Int) {
        guard request == returnRequest else { return }
        returnLayoutComplete = true
    }
}
#endif
