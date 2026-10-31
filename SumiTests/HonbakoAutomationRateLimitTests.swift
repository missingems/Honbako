@testable import Sumi
import Foundation
import Testing

@Suite struct HonbakoAutomationRateLimitTests {
    private typealias Limit = HonbakoAutomationRateLimit
    private let now = Date(timeIntervalSince1970: 1_793_440_000) // 2026-10-31T09:46:40Z

    @Test("Retry-After is read as seconds or an HTTP-date; anything else is ignored")
    func parsesRetryAfter() {
        #expect(Limit.retryAfter("60", now: now) == 60)
        #expect(Limit.retryAfter(" 51200 ", now: now) == 51_200)
        #expect(Limit.retryAfter("Sat, 31 Oct 2026 09:47:40 GMT", now: now) == 60)
        #expect(Limit.retryAfter("Sat, 31 Oct 2026 09:00:00 GMT", now: now) == 0)
        for junk in [nil, "", "-5", "soon", "1.5"] { #expect(Limit.retryAfter(junk, now: now) == nil) }
    }

    @Test("The server's wait is honoured; without one, the wait doubles from 3 s to at most 5 minutes")
    func backOff() {
        #expect(Limit.delay(retryAfter: 60, attempt: 7) == 60)
        #expect(Limit.delay(retryAfter: 0, attempt: 1) == 1)
        #expect(Limit.delay(retryAfter: 200_000, attempt: 1) == 86_400)
        #expect((1...9).map { Limit.delay(retryAfter: nil, attempt: $0) } == [3, 6, 12, 24, 48, 96, 192, 300, 300])
        #expect(Limit.delay(retryAfter: nil, attempt: 0) == 3)
    }

    @Test("A short wait retries quietly; the daily limit says when the connection resumes")
    func messages() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(Limit.message(resumeAt: now.addingTimeInterval(60), now: now, calendar: calendar)
            == String(localized: "Honbako is sending too many requests. It will try again in a moment."))
        let midnight = Date(timeIntervalSince1970: 1_793_491_200) // 2026-11-01T00:00:00Z
        let daily = Limit.message(resumeAt: midnight, now: now, calendar: calendar)
        #expect(daily.hasPrefix(String(localized: "Your AI connection has reached today’s limit and resumes at").prefix(30)))
        #expect(daily.contains(midnight.formatted(.dateTime.weekday(.wide).hour().minute())))
        let later = now.addingTimeInterval(3600)
        #expect(Limit.message(resumeAt: later, now: now, calendar: calendar).contains(later.formatted(date: .omitted, time: .shortened)))
    }
}
