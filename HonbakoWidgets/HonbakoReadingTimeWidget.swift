import SwiftUI
import WidgetKit

struct HonbakoReadingTimeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HonbakoWidgetSnapshot.timeKind, provider: HonbakoWidgetProvider()) { entry in
            HonbakoTimeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Reading Time")
        .description("Today’s reading time and your week in manga.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
