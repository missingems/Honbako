#if SUMI
import SwiftUI

struct HonbakoJapaneseWordLabel: View {
    let word: HonbakoJapaneseWord
    var selected = false

    static func accessibilityText(for word: HonbakoJapaneseWord) -> String {
        var parts = [word.text]
        if let kana = word.reading, kana != word.text { parts.append(kana) }
        if let romaji = word.romaji { parts.append(romaji) } else { parts.append(String(localized: "Reading Unavailable")) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(word.text).font(.body).foregroundStyle(.primary)
            if let kana = word.reading, kana != word.text {
                Text(kana).font(.caption).foregroundStyle(.secondary)
            }
            if let romaji = word.romaji {
                Text(romaji).font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Reading Unavailable").font(.caption).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(selected ? Color(uiColor: .tertiarySystemFill) : Color(uiColor: .tertiarySystemGroupedBackground),
                    in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(selected ? 0.85 : 0.2), lineWidth: selected ? 2 : 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
