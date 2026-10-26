@testable import Sumi
import Foundation
import Testing

struct HonbakoChapterAlertPreferencesTests {
    @Test("New titles opt in without conflating source and title identifiers")
    func independentPreferences() throws {
        let name = "Honbako.Alerts.Tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = MangaIdentifier(sourceKey: "a.b", mangaKey: "c")
        let second = MangaIdentifier(sourceKey: "a", mangaKey: "b.c")
        #expect(HonbakoChapterAlerts.preferenceEnabled(for: first, defaults: defaults))
        #expect(HonbakoChapterAlerts.preferenceEnabled(for: second, defaults: defaults))
        HonbakoChapterAlerts.setPreference(false, for: first, defaults: defaults)
        #expect(!HonbakoChapterAlerts.preferenceEnabled(for: first, defaults: defaults))
        #expect(HonbakoChapterAlerts.preferenceEnabled(for: second, defaults: defaults))
    }
}
