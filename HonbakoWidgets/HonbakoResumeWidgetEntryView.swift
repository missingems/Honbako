import SwiftUI
import WidgetKit

struct HonbakoResumeWidgetEntryView: View {
    let entry: HonbakoWidgetEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        HonbakoResumeWidgetView(snapshot: entry.snapshot, expanded: family != .systemSmall)
            .padding(family == .systemSmall ? 8 : 16)
            .containerBackground(.background, for: .widget)
    }
}
