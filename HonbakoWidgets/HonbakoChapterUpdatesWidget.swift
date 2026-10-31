import SwiftUI
import WidgetKit

struct HonbakoChapterUpdatesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HonbakoWidgetSnapshot.updatesKind, provider: HonbakoWidgetProvider()) { entry in
            HonbakoUpdatesWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("New Chapters")
        .description("Recent chapter updates from your library.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
