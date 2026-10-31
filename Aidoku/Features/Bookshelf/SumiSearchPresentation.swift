#if SUMI
import Combine
import Foundation

@MainActor
final class SumiSearchPresentation: ObservableObject {
    @Published var isPresented = false
    @Published var query = ""
    @Published private(set) var requestsKeyboard = true
    @Published private(set) var pullProgress: CGFloat = 0

    var revealProgress: CGFloat { isPresented ? 1 : pullProgress }

    func updatePull(distance: CGFloat) {
        guard !isPresented else { return }
        let progress = SumiSearchPull.progress(distance: distance)
        guard progress != pullProgress else { return }
        pullProgress = progress
    }
    func finishPull() {
        guard pullProgress != 0 else { return }
        pullProgress = 0
    }
    func reveal() { requestsKeyboard = true; isPresented = true; pullProgress = 0 }
    func suspendKeyboard() { if requestsKeyboard { requestsKeyboard = false } }
    func dismiss() { isPresented = false; pullProgress = 0 }
}
#endif
