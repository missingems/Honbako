@testable import Sumi
import Testing

@MainActor
struct HonbakoWelcomeNavigationTests {
    @Test("Next and native Back share one persistent navigation history")
    func nativeHistory() {
        let navigation = HonbakoWelcomeNavigation()
        #expect(navigation.currentPage == .library)
        #expect(navigation.path.isEmpty)
        navigation.advance()
        #expect(navigation.path == [.assistant])
        navigation.advance()
        #expect(navigation.path == [.assistant, .plans])
        navigation.advance()
        #expect(navigation.path == [.assistant, .plans])
        navigation.path.removeLast()
        #expect(navigation.currentPage == .assistant)
        navigation.path.removeLast()
        #expect(navigation.currentPage == .library)
    }

    @Test("Sidebar selection resolves to the same stack used on compact screens")
    func sidebarSelection() {
        let navigation = HonbakoWelcomeNavigation()
        navigation.select(.plans)
        #expect(navigation.path == [.assistant, .plans])
        navigation.select(.plans)
        #expect(navigation.path == [.assistant, .plans])
        navigation.select(.assistant)
        #expect(navigation.path == [.assistant])
        navigation.select(.library)
        #expect(navigation.path.isEmpty)
        let preview = HonbakoWelcomeNavigation(startingAt: .plans)
        #expect(preview.path == [.assistant, .plans])
    }
}
