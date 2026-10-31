@testable import Sumi
import Foundation
import Testing

@MainActor
struct HonbakoChapterAvailabilityTests {
    @Test("Confirmed state is scoped by source instance, version, manga and chapter and recovers after refresh")
    func identityAndRecovery() {
        let first = NSObject(), second = NSObject()
        let key = SumiChapterPageListCache.Key(sourceInstance: ObjectIdentifier(first), sourceKey: "server", mangaKey: "one", chapterKey: "1", language: "en")
        let otherBook = SumiChapterPageListCache.Key(sourceInstance: ObjectIdentifier(first), sourceKey: "server", mangaKey: "two", chapterKey: "1", language: "en")
        let otherAccount = SumiChapterPageListCache.Key(sourceInstance: ObjectIdentifier(second), sourceKey: "server", mangaKey: "one", chapterKey: "1", language: "en")
        let registry = HonbakoChapterAvailability()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        registry.record(.unavailable, for: key, expires: now.addingTimeInterval(300))
        #expect(registry.state(for: key, now: now) == .unavailable)
        #expect(registry.state(for: otherBook, now: now) == .unknown)
        #expect(registry.state(for: otherAccount, now: now) == .unknown)
        registry.clear(sourceKey: "server", mangaKey: "one")
        #expect(registry.state(for: key, now: now) == .unknown)
        registry.record(.available, for: key, expires: now.addingTimeInterval(60))
        #expect(registry.state(for: key, now: now) == .available)
        #expect(registry.state(for: key, now: now.addingTimeInterval(61)) == .unknown)
    }

    @Test("Only provider-confirmed absence is permanent enough to gray a chapter")
    func conservativeFailureClassification() {
        #expect(HonbakoChapterAvailability.confirmsUnavailable(HonbakoMangaDexError.unavailableChapter))
        #expect(HonbakoChapterAvailability.confirmsUnavailable(HonbakoMangaDexError.requestFailed(404)))
        #expect(HonbakoChapterAvailability.confirmsUnavailable(HonbakoMangaDexError.requestFailed(410)))
        for error in [URLError(.timedOut) as Error, CancellationError(), HonbakoMangaDexError.invalidResponse,
                      HonbakoMangaDexError.requestFailed(401), HonbakoMangaDexError.requestFailed(403),
                      HonbakoMangaDexError.requestFailed(429), HonbakoMangaDexError.requestFailed(500)] {
            #expect(!HonbakoChapterAvailability.confirmsUnavailable(error))
        }
    }
}
