#if SUMI || HONBAKO_WIDGET_EXTENSION
import SwiftUI
import WidgetKit

struct HonbakoUpdatesWidgetView: View {
    let snapshot: HonbakoWidgetSnapshot
    let date: Date
    var large = false

    var body: some View {
        Group {
            if snapshot.hasPro(at: date) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("New chapters", systemImage: "sparkle").font(.headline)
                        Spacer(minLength: 0)
                    }
                    if snapshot.updates.isEmpty {
                        Spacer(minLength: 0)
                        Text("All caught up.").font(.title3.weight(.semibold))
                        Text("New chapters appear after your library checks for updates.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    } else {
                        ForEach(Array(snapshot.updates.prefix(large ? 4 : 1))) { book in
                            Link(destination: book.resumeURL ?? URL(string: "honbako://widget/library")!) {
                                HStack(spacing: 10) {
                                    HonbakoWidgetCover(book: book).frame(width: 36, height: 49)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(book.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                        Text(book.chapter ?? String(localized: "New chapter"))
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Text("+\(book.updateCount)").font(.system(.subheadline, design: .rounded, weight: .bold))
                                        .foregroundStyle(HonbakoPalette.accent)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    if let checked = snapshot.libraryCheckedAt {
                        Text("Library updated \(checked.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } else {
                HonbakoWidgetProPrompt(title: "New chapters", symbol: "sparkle", detail: "Keep up with your collection.")
            }
        }
        .widgetURL(URL(string: snapshot.hasPro(at: date) ? "honbako://widget/library" : "honbako://widget/pro"))
    }
}

#endif
