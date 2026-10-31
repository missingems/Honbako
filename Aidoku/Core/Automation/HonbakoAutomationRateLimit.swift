#if SUMI
import Foundation

/// How a device waits after the hosted server answers 429. Hosting runs on daily allowances shared
/// by every account, so a limited device pauses its polling and page sharing instead of retrying.
enum HonbakoAutomationRateLimit {
    /// Without Retry-After: 3 s, doubling per refusal, at most 5 minutes.
    static let firstDelay: TimeInterval = 3, longestGuess: TimeInterval = 300
    /// Waits longer than this are the daily limit, which resumes at 00:00 UTC.
    static let dailyThreshold: TimeInterval = 600

    /// Retry-After as delay-seconds or an HTTP-date.
    static func retryAfter(_ header: String?, now: Date) -> TimeInterval? {
        guard let value = header?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = Int(value), seconds >= 0 { return TimeInterval(seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }

    /// The server's wait when it gives one (at least 1 s, at most a day), else exponential back-off.
    static func delay(retryAfter: TimeInterval?, attempt: Int) -> TimeInterval {
        if let retryAfter { return min(max(retryAfter, 1), 86_400) }
        return min(firstDelay * pow(2, Double(max(0, attempt - 1))), longestGuess)
    }

    static func message(resumeAt: Date, now: Date, calendar: Calendar = .current) -> String {
        guard resumeAt.timeIntervalSince(now) > dailyThreshold else {
            return String(localized: "Honbako is sending too many requests. It will try again in a moment.")
        }
        let time = calendar.isDate(resumeAt, inSameDayAs: now)
            ? resumeAt.formatted(date: .omitted, time: .shortened)
            : resumeAt.formatted(.dateTime.weekday(.wide).hour().minute())
        return String(localized: "Your AI connection has reached today’s limit and resumes at \(time).")
    }
}
#endif
