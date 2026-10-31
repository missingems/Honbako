#if SUMI || HONBAKO_WIDGET_EXTENSION
import SwiftUI
import WidgetKit

struct HonbakoReadingTimeWidgetView: View {
    let snapshot: HonbakoWidgetSnapshot
    let date: Date
    var expanded = false

    var body: some View {
        Group {
            if snapshot.hasPro(at: date) {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("READING TIME").font(.system(.caption2, design: .rounded, weight: .bold)).tracking(1)
                        Spacer(minLength: 0)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(minutes.formatted()).font(.system(size: 46, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.5)
                            Text("min").font(.caption.weight(.semibold))
                        }
                        Text("Today").font(.subheadline.weight(.medium))
                        if !expanded { weeklyBars.frame(height: 22).padding(.top, 4) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if expanded {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "book.pages.fill").font(.title2)
                            weeklyBars.frame(height: 55)
                            Text("Last 7 days").font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .foregroundStyle(Color.primary)
            } else {
                HonbakoWidgetProPrompt(title: "Reading time", symbol: "clock", detail: "Your reading, at a glance.")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(snapshot.hasPro(at: date) ? String(localized: "Reading time today: \(minutes) minutes") : String(localized: "Reading time widget. Open Honbako to enable."))
        .widgetURL(URL(string: snapshot.hasPro(at: date) ? "honbako://widget/library" : "honbako://widget/pro"))
    }

    private var minutes: Int { Int(snapshot.secondsRead(on: date) / 60) }
    private var weeklyBars: some View {
        let days = (0..<7).compactMap { offset -> HonbakoWidgetSnapshot.ReadingDay? in
            guard let day = Calendar.current.date(byAdding: .day, value: offset - 6,
                to: Calendar.current.startOfDay(for: date)) else { return nil }
            return .init(date: day, seconds: snapshot.secondsRead(on: day))
        }
        let maximum = max(60, days.map(\.seconds).max() ?? 60)
        return GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days, id: \.date) { day in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Calendar.current.isDate(day.date, inSameDayAs: date) ? HonbakoPalette.accent : HonbakoPalette.accent.opacity(0.25))
                        .frame(height: max(3, geometry.size.height * max(0, day.seconds) / maximum))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
    }
}

#endif
