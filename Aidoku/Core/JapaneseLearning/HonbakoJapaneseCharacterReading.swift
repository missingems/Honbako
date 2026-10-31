import Foundation

/// A source glyph (or an inseparable sound such as きゃ) and its pronunciation.
/// Ranges stay in the original OCR string. Kanji compounds are kept together
/// when their contextual reading cannot truthfully be assigned to each glyph.
struct HonbakoJapaneseCharacterReading: Identifiable, Equatable, Sendable {
    var id: Int { range.location }
    let wordID: Int
    let text: String
    let romaji: String
    let range: NSRange
}

enum HonbakoJapaneseCharacterReadings {
    static func units(for word: HonbakoJapaneseWord) -> [HonbakoJapaneseCharacterReading] {
        let source = word.text
        guard !source.isEmpty else { return [] }
        let glyphs = source.indices.map { index -> (text: String, kana: String, range: NSRange) in
            let end = source.index(after: index)
            let text = String(source[index..<end])
            let normalized = text.precomposedStringWithCompatibilityMapping
            return (text, normalized.applyingTransform(.hiraganaToKatakana, reverse: true) ?? normalized,
                    NSRange(index..<end, in: source))
        }
        // An all-kanji compound has no evidence for dividing its reading.
        // A single kanji is already a genuine character-sized anchor.
        guard glyphs.allSatisfy({ isKana($0.kana) || $0.kana == "ー" }) else {
            return contextualUnits(for: word, glyphs: glyphs)
        }
        // Respect an explicit contextual correction only when one source glyph
        // owns the entire reading. Never infer particle pronunciation by spelling
        // or redistribute a corrected word reading across unrelated characters.
        if glyphs.count == 1, let reading = word.reading {
            let normalized = reading.precomposedStringWithCompatibilityMapping
            let kana = normalized.applyingTransform(.hiraganaToKatakana, reverse: true) ?? normalized
            if kana != glyphs[0].kana, isKana(kana),
               let latin = kana.applyingTransform(.toLatin, reverse: false),
               !latin.isEmpty, !HonbakoJapaneseText.containsJapanese(latin) {
                return [.init(wordID: word.id, text: source, romaji: latin, range: word.range)]
            }
        }
        var groups: [(text: String, kana: String, range: NSRange)] = []
        for glyph in glyphs {
            if "ゃゅょぁぃぅぇぉゎ".contains(glyph.kana), var previous = groups.popLast() {
                previous.text += glyph.text
                previous.kana += glyph.kana
                previous.range.length = NSMaxRange(glyph.range) - previous.range.location
                groups.append(previous)
            } else { groups.append(glyph) }
        }
        var result: [HonbakoJapaneseCharacterReading] = []
        for (index, group) in groups.enumerated() {
            let latin: String?
            if group.kana == "っ" {
                let next = groups.dropFirst(index + 1).first?.kana.applyingTransform(.toLatin, reverse: false)
                // A small tsu is a held/doubled consonant, never an extra "tsu".
                if let next, next.hasPrefix("ch") { latin = "t" }
                else if let first = next?.first, "bcdfghjklmnpqrstvwxyz".contains(first) { latin = String(first) }
                else { latin = nil }
            } else if group.kana == "ー" {
                // The prolonged-sound mark lengthens the preceding vowel.
                latin = result.last?.romaji.last(where: { "aeiou".contains($0) }).map(String.init)
            } else { latin = group.kana.applyingTransform(.toLatin, reverse: false) }
            guard let latin, !latin.isEmpty, !HonbakoJapaneseText.containsJapanese(latin) else { continue }
            result.append(.init(wordID: word.id, text: group.text, romaji: latin,
                range: NSRange(location: word.range.location + group.range.location, length: group.range.length)))
        }
        return result
    }

    private static func isKana(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) }
    }

    private static func contextualUnits(
        for word: HonbakoJapaneseWord,
        glyphs: [(text: String, kana: String, range: NSRange)]
    ) -> [HonbakoJapaneseCharacterReading] {
        guard let reading = word.reading, let romaji = word.romaji, !romaji.isEmpty else { return [] }
        // Okurigana supplies an exact suffix anchor. Do not divide a dictionary
        // reading in proportion to kanji count (大人→otona is indivisible).
        let suffixStart = glyphs.lastIndex(where: { !isKana($0.kana) && $0.kana != "ー" }).map { $0 + 1 } ?? 0
        let suffix = glyphs.dropFirst(suffixStart).map(\.kana).joined()
        guard !suffix.isEmpty, reading.hasSuffix(suffix), suffixStart > 0 else {
            return [.init(wordID: word.id, text: word.text, romaji: romaji, range: word.range)]
        }
        let prefixReading = String(reading.dropLast(suffix.count))
        let prefixLength = glyphs[suffixStart].range.location
        guard !prefixReading.isEmpty,
              let prefixLatin = prefixReading.applyingTransform(.toLatin, reverse: false),
              !HonbakoJapaneseText.containsJapanese(prefixLatin) else { return [] }
        let prefixText = (word.text as NSString).substring(to: prefixLength)
        let tailText = (word.text as NSString).substring(from: prefixLength)
        let tail = HonbakoJapaneseWord(id: word.id, text: tailText, reading: suffix, romaji: nil,
            readingIsEstimated: word.readingIsEstimated,
            range: NSRange(location: word.range.location + prefixLength, length: word.range.length - prefixLength))
        return [.init(wordID: word.id, text: prefixText, romaji: prefixLatin,
                      range: NSRange(location: word.range.location, length: prefixLength))] + units(for: tail)
    }
}
