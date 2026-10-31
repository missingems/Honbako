#if SUMI
import Observation

/// One native navigation history is retained across resizing and folding.
@MainActor
@Observable
final class HonbakoWelcomeNavigation {
    var path: [HonbakoWelcomePage]
    var currentPage: HonbakoWelcomePage { path.last ?? .library }

    init(startingAt page: HonbakoWelcomePage = .library) {
        path = page.navigationPath
    }

    func select(_ page: HonbakoWelcomePage) {
        guard currentPage != page else { return }
        path = page.navigationPath
    }

    func advance() {
        guard let next = currentPage.next else { return }
        path.append(next)
    }
}
#endif
