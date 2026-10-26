#if SUMI
import Combine
import Foundation

@MainActor
final class SumiSearchPresentation: ObservableObject {
    @Published var isPresented = false
    @Published var query = ""
    @Published private(set) var pullProgress: CGFloat = 0

    var revealProgress: CGFloat { isPresented ? 1 : pullProgress }

    func updatePull(distance: CGFloat) {
        guard !isPresented else { return }
        pullProgress = min(1, max(0, distance / 52))
    }
    func finishPull() { pullProgress = 0 }
    func reveal() { isPresented = true; pullProgress = 0 }
    func dismiss() { isPresented = false; pullProgress = 0 }
}
#endif
