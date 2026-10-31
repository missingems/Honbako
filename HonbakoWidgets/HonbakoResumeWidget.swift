import SwiftUI
import WidgetKit

struct HonbakoResumeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HonbakoWidgetSnapshot.resumeKind, provider: HonbakoWidgetProvider()) { entry in
            HonbakoResumeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Continue Reading")
        .description("Your last manga, ready to resume. Free for everyone.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
