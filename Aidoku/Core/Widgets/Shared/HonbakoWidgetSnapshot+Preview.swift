#if SUMI || HONBAKO_WIDGET_EXTENSION
import Foundation

extension HonbakoWidgetSnapshot {
    /// Only WidgetKit's gallery and previews use examples; installed widgets
    /// always read the real shared snapshot, including honest empty states.
    static var preview: Self {
        let now = Date.now
        return .init(generatedAt: now, proExpiresAt: now.addingTimeInterval(86400),
            resume: .init(sourceID: "preview", mangaID: "paper", title: "Paper Moon", chapter: "Chapter 3", page: 12, totalPages: 32),
            updates: [.init(sourceID: "preview", mangaID: "paper", title: "Paper Moon", chapter: "Chapter 4", updateCount: 2),
                      .init(sourceID: "preview", mangaID: "city", title: "The Quiet City", chapter: "Chapter 8", updateCount: 1)],
            readingDays: (0..<7).map { offset in
                .init(date: Calendar.current.date(byAdding: .day, value: offset - 6, to: Calendar.current.startOfDay(for: now)) ?? now,
                      seconds: [720.0, 1620, 480, 2100, 1080, 1560, 1440][offset])
            }, libraryCheckedAt: now)
    }
}

#endif
