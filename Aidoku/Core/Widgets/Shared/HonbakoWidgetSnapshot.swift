#if SUMI || HONBAKO_WIDGET_EXTENSION
import Foundation

/// Only display data crosses into the widget process. Source credentials and
/// the library database remain in the app's private container.
struct HonbakoWidgetSnapshot: Codable, Equatable, Sendable {
    static let groupID = "group.com.missingems.honbaku.widgets"
    static let fileName = "widgets-v1.json"
    static let resumeKind = "Honbako.Resume"
    static let timeKind = "Honbako.ReadingTime"
    static let updatesKind = "Honbako.Updates"

    var generatedAt: Date
    var proExpiresAt: Date?
    var resume: Book?
    var updates: [Book]
    var readingDays: [ReadingDay]
    var libraryCheckedAt: Date?

    struct Book: Codable, Equatable, Identifiable, Sendable {
        var sourceID: String
        var mangaID: String
        var title: String
        var chapter: String?
        var page: Int?
        var totalPages: Int?
        var coverFile: String?
        var updateCount = 0
        var id: String { sourceID + "\u{0}" + mangaID }
        var resumeURL: URL? {
            var components = URLComponents()
            components.scheme = "honbako"
            components.host = "widget"
            components.path = "/resume"
            components.queryItems = [.init(name: "source", value: sourceID), .init(name: "manga", value: mangaID)]
            return components.url
        }
        var progress: Double? {
            guard let page, let totalPages, totalPages > 0 else { return nil }
            return min(1, max(0, Double(page) / Double(totalPages)))
        }
    }

    struct ReadingDay: Codable, Equatable, Sendable {
        var date: Date
        var seconds: TimeInterval
    }

    static var empty: Self {
        .init(generatedAt: .distantPast, resume: nil, updates: [], readingDays: [])
    }

    func hasPro(at date: Date) -> Bool { proExpiresAt.map { $0 > date } ?? false }

    /// Expiry and midnight entries must not depend on the OS granting another
    /// opportunistic reload, which can be delayed by widget budgets.
    func timelineDates(now: Date, calendar: Calendar = .current) -> [Date] {
        var dates = [now]
        let today = calendar.startOfDay(for: now)
        for day in 1...7 {
            if let midnight = calendar.date(byAdding: .day, value: day, to: today) { dates.append(midnight) }
        }
        if let expiry = proExpiresAt, expiry > now { dates.append(expiry) }
        return Array(Set(dates)).sorted()
    }

    func secondsRead(on date: Date, calendar: Calendar = .current) -> TimeInterval {
        readingDays.filter { calendar.isDate($0.date, inSameDayAs: date) }.reduce(0) { $0 + max(0, $1.seconds) }
    }

    /// Split sessions at midnight so yesterday's reading never becomes today's.
    static func readingDays(sessions: [(start: Date, end: Date)], now: Date,
                            calendar: Calendar = .current) -> [ReadingDay] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return [] }
        var totals: [Date: TimeInterval] = [:]
        for session in sessions {
            var cursor = max(start, session.start)
            let end = min(now, session.end)
            guard end > cursor else { continue }
            while cursor < end {
                let day = calendar.startOfDay(for: cursor)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > cursor else { break }
                let boundary = min(next, end)
                totals[day, default: 0] += boundary.timeIntervalSince(cursor)
                cursor = boundary
            }
        }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return ReadingDay(date: day, seconds: totals[day, default: 0])
        }
    }

    static func resumeTarget(from url: URL) -> (source: String, manga: String)? {
        guard url.scheme == "honbako", url.host == "widget", url.path == "/resume",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        guard items.filter({ $0.name == "source" }).count == 1,
              items.filter({ $0.name == "manga" }).count == 1,
              let source = items.first(where: { $0.name == "source" })?.value,
              let manga = items.first(where: { $0.name == "manga" })?.value,
              !source.isEmpty, !manga.isEmpty, source.utf8.count <= 2048, manga.utf8.count <= 4096 else { return nil }
        return (source, manga)
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    static func read(from directory: URL? = containerURL) -> Self {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)),
              data.count < 1_000_000,
              let snapshot = try? JSONDecoder().decode(Self.self, from: data) else { return .empty }
        return snapshot
    }

    static func coverURL(file: String?, directory: URL? = containerURL) -> URL? {
        guard let directory, let file, file.hasSuffix(".jpg"),
              !file.contains("/"), !file.contains("\\"), !file.contains("..") else { return nil }
        return directory.appendingPathComponent("covers", isDirectory: true).appendingPathComponent(file)
    }

    /// Do not retain Pro-only library metadata after a downgrade.
    func removingLockedData(at date: Date) -> Self {
        guard !hasPro(at: date) else { return self }
        var result = self
        result.updates = []
        result.readingDays = []
        return result
    }
}

#endif
