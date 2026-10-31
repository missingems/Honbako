import SwiftUI
import WidgetKit

struct HonbakoUpdatesWidgetEntryView: View {
    let entry: HonbakoWidgetEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        HonbakoUpdatesWidgetView(snapshot: entry.snapshot, date: entry.date, large: family == .systemLarge)
            .containerBackground(.background, for: .widget)
    }
}
