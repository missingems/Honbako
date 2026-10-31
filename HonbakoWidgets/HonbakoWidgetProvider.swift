import SwiftUI
import WidgetKit

struct HonbakoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HonbakoWidgetEntry { .init(date: .now, snapshot: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (HonbakoWidgetEntry) -> Void) {
        completion(.init(date: .now, snapshot: context.isPreview ? .preview : .read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HonbakoWidgetEntry>) -> Void) {
        let now = Date.now
        let snapshot = HonbakoWidgetSnapshot.read().removingLockedData(at: now)
        let entries = snapshot.timelineDates(now: now).map { date in
            HonbakoWidgetEntry(date: date, snapshot: snapshot.removingLockedData(at: date))
        }
        let nextRefresh = now.addingTimeInterval(30 * 60)
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }
}
