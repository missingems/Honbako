#if SUMI || HONBAKO_WIDGET_EXTENSION
import SwiftUI
import WidgetKit

struct HonbakoResumeWidgetView: View {
    let snapshot: HonbakoWidgetSnapshot
    var expanded = false

    var body: some View {
        Group {
            if let book = snapshot.resume {
                if expanded {
                    HStack(spacing: 16) {
                        HonbakoWidgetCover(book: book)
                            .frame(width: 82)
                            .rotationEffect(.degrees(-4))
                            .shadow(color: .black.opacity(0.15), radius: 3, y: 3)
                        VStack(alignment: .leading, spacing: 6) {
                            if let chapter = book.chapter { Text(chapter).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            if let page = book.page, page > 0 {
                                Text("Page \(page)").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            resumeLabel
                                .accessibilityLabel("Resume \(book.title)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ZStack(alignment: .bottomLeading) {
                        HonbakoWidgetCover(book: book)
                        LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                        Label("Resume", systemImage: "play.fill")
                            .font(.caption2.weight(.semibold))
                            .accessibilityLabel("Resume \(book.title)")
                        .foregroundStyle(.white)
                        .padding(12)
                    }
                    .clipShape(.rect(cornerRadius: 14))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Spacer(minLength: 0)
                    Image(systemName: "book.closed").font(.title)
                    Text("Your next chapter awaits.").font(.headline)
                    Text("Open a manga to start reading.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .widgetURL(snapshot.resume?.resumeURL ?? URL(string: "honbako://widget/library"))
    }

    private var resumeLabel: some View {
        Label("Resume", systemImage: "play.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(HonbakoPalette.onAction)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(HonbakoPalette.action, in: .capsule)
    }
}

#endif
