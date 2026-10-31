import SwiftUI
import WidgetKit

struct HonbakoTimeWidgetEntryView: View {
    let entry: HonbakoWidgetEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        HonbakoReadingTimeWidgetView(snapshot: entry.snapshot, date: entry.date, expanded: family != .systemSmall)
            .containerBackground(HonbakoPalette.accent.opacity(0.08), for: .widget)
    }
}
