#if SUMI || HONBAKO_WIDGET_EXTENSION
import SwiftUI

struct HonbakoWidgetProPrompt: View {
    let title: LocalizedStringKey
    let symbol: String
    let detail: LocalizedStringKey
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: symbol).font(.title2)
                Spacer(minLength: 0)
                Image(systemName: "lock.fill").font(.caption)
            }
            Spacer(minLength: 0)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
            Text("Open Honbako").font(.caption2.weight(.bold)).foregroundStyle(HonbakoPalette.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#endif
