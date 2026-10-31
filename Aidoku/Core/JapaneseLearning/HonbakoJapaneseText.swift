import CoreFoundation
import Foundation

enum HonbakoJapaneseText {
    static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
                case 0x3041...0x3096, 0x30A1...0x30FA, 0xFF66...0xFF9D,
                     0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x3134F:
                    return true
                default:
                    return false
            }
        }
    }

    /// A reading aid, not a dictionary definition. System-generated kanji readings may be ambiguous.
    static func reading(for rawText: String) -> HonbakoJapaneseReading {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard containsJapanese(text) else {
            return .init(text: text, reading: nil, romaji: nil, readingIsEstimated: false)
        }
        let words = words(for: text)
        let source = text as NSString
        var kana = ""
        var latin = ""
        var previousEnd = 0
        var complete = !words.isEmpty
        for word in words {
            let gap = source.substring(with: NSRange(location: previousEnd, length: word.range.location - previousEnd))
                .precomposedStringWithCompatibilityMapping
            guard !containsJapanese(gap), let wordKana = word.reading, let wordLatin = word.romaji else {
                complete = false
                break
            }
            kana += gap + wordKana
            latin += gap
            if gap.isEmpty, !latin.isEmpty { latin += " " }
            latin += wordLatin
            previousEnd = NSMaxRange(word.range)
        }
        let suffix = source.substring(from: previousEnd).precomposedStringWithCompatibilityMapping
        if containsJapanese(suffix) { complete = false }
        kana += suffix
        latin += suffix
        return .init(text: text, reading: complete ? kana : nil, romaji: complete ? latin : nil,
                     readingIsEstimated: !complete || words.contains(where: \.readingIsEstimated), words: words)
    }

    /// Japanese tokenization works on the source string before normalization.
    /// This preserves UTF-16 offsets through emoji, half-width kana and dakuten.
    static func words(for text: String) -> [HonbakoJapaneseWord] {
        guard containsJapanese(text) else { return [] }
        let source = text as NSString
        // Analyze lexical content without edge punctuation. On some system
        // dictionaries a terminal 。 changes あした into individual syllables.
        // A subrange of the original string fixes that without shifting anchors.
        let lexicalText = text.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        guard !lexicalText.isEmpty, let lexicalRange = text.range(of: lexicalText) else { return [] }
        let analysisRange = NSRange(lexicalRange, in: text)
        let tokenizer = CFStringTokenizerCreate(
            nil, text as CFString, CFRange(location: analysisRange.location, length: analysisRange.length),
            kCFStringTokenizerUnitWord, Locale(identifier: "ja_JP") as CFLocale
        )
        var words: [HonbakoJapaneseWord] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer).rawValue != 0 {
            let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard tokenRange.location >= 0, tokenRange.length > 0,
                  tokenRange.location <= source.length - tokenRange.length else { continue }
            let range = NSRange(location: tokenRange.location, length: tokenRange.length)
            let word = source.substring(with: range)
            guard containsJapanese(word), Range(range, in: text) != nil else { continue }
            // Read each Japanese dictionary token on its own. Some OS versions
            // infer Chinese for a kanji-only phrase surrounded by punctuation.
            let reading = phraseReading(for: word)
            let unsafeLatin = reading.readingIsEstimated && reading.romaji.map { !isJapaneseDictionaryLatin($0) } == true
            words.append(.init(id: range.location, text: word,
                               reading: unsafeLatin ? nil : reading.reading,
                               romaji: unsafeLatin ? nil : reading.romaji,
                               readingIsEstimated: reading.readingIsEstimated, range: range))
        }
        return words
    }

    private static func isJapaneseDictionaryLatin(_ text: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 '-")
        return !text.isEmpty && text.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func phraseReading(for rawText: String) -> HonbakoJapaneseReading {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard containsJapanese(text) else {
            return .init(text: text, reading: nil, romaji: nil, readingIsEstimated: false)
        }
        let normalized = text.precomposedStringWithCompatibilityMapping
        let containsKanji = normalized.unicodeScalars.contains { scalar in
            switch scalar.value {
                case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x3134F: return true
                default: return false
            }
        }
        if !containsKanji {
            let kana = normalized.applyingTransform(.hiraganaToKatakana, reverse: true) ?? normalized
            // Generic Latin transforms are safe only for kana: kanji would otherwise become Chinese pinyin.
            let romanization = kana.applyingTransform(.toLatin, reverse: false)
            return .init(text: text, reading: kana, romaji: romanization, readingIsEstimated: false)
        }
        return tokenize(text: text, normalized: normalized)
    }

    private static func tokenize(text: String, normalized: String) -> HonbakoJapaneseReading {
        let source = normalized as NSString
        let tokenizer = CFStringTokenizerCreate(
            nil,
            normalized as CFString,
            CFRange(location: 0, length: source.length),
            kCFStringTokenizerUnitWord | kCFStringTokenizerAttributeLatinTranscription,
            Locale(identifier: "ja_JP") as CFLocale
        )
        var kanaParts: [String] = []
        var latinParts: [String] = []
        var previousEnd = 0
        var complete = true
        while CFStringTokenizerAdvanceToNextToken(tokenizer).rawValue != 0 {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard range.location >= previousEnd, range.length > 0, range.location + range.length <= source.length else {
                complete = false
                break
            }
            if range.location > previousEnd {
                let gap = source.substring(with: NSRange(location: previousEnd, length: range.location - previousEnd))
                kanaParts.append(gap)
                latinParts.append(gap)
            }
            let word = source.substring(with: NSRange(location: range.location, length: range.length))
            let transcription = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
            if let transcription, !transcription.isEmpty, !containsJapanese(transcription),
               let kana = transcription.applyingTransform(.latinToHiragana, reverse: false) {
                kanaParts.append(kana)
                latinParts.append(transcription)
            } else if !containsJapanese(word) {
                kanaParts.append(word)
                latinParts.append(word)
            } else {
                // Do not offer a partial sentence as if all kanji had been read successfully.
                complete = false
                break
            }
            previousEnd = range.location + range.length
        }
        if previousEnd < source.length {
            let suffix = source.substring(from: previousEnd)
            if containsJapanese(suffix) { complete = false }
            kanaParts.append(suffix)
            latinParts.append(suffix)
        }
        guard complete, !kanaParts.isEmpty else {
            return .init(text: text, reading: nil, romaji: nil, readingIsEstimated: true)
        }
        return .init(
            text: text,
            reading: kanaParts.joined(),
            romaji: latinParts.joined(separator: " ").replacingOccurrences(of: "  ", with: " "),
            readingIsEstimated: true
        )
    }
}
