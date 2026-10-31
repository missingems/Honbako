@testable import Sumi
import CoreGraphics
import Foundation
import Testing

@Suite struct HonbakoJapaneseCharacterReadingTests {
    @Test("Kana readings follow individual source characters and preserve source offsets")
    func kanaCharacterReadings() {
        let word = makeWord("ました", reading: "ました", romaji: "mashita", location: 3)
        let units = HonbakoJapaneseCharacterReadings.units(for: word)
        #expect(units.map(\.text) == ["ま", "し", "た"])
        #expect(units.map(\.romaji) == ["ma", "shi", "ta"])
        #expect(units.map(\.range) == [NSRange(location: 3, length: 1), NSRange(location: 4, length: 1), NSRange(location: 5, length: 1)])
        #expect(Set(units.map(\.id)).count == 3)
        #expect(units.allSatisfy { $0.wordID == 3 })
    }

    @Test("Combined kana, small tsu and prolonged vowels preserve real pronunciation")
    func combinedSounds() {
        #expect(units("きゃく").map(\.text) == ["きゃ", "く"])
        #expect(units("きゃく").map(\.romaji) == ["kya", "ku"])
        #expect(units("まっちゃ").map(\.romaji) == ["ma", "t", "cha"])
        #expect(units("がっこう").map(\.romaji) == ["ga", "k", "ko", "u"])
        #expect(units("コーヒー").map(\.romaji) == ["ko", "o", "hi", "i"])
        #expect(units("っ").isEmpty, "An isolated small tsu must not claim to be pronounced tsu")
    }

    @Test("A corrected single-character reading wins without guessing particle pronunciation")
    func explicitSingleCharacterReading() {
        for (text, reading, expected) in [("は", "わ", "wa"), ("へ", "え", "e"), ("を", "お", "o")] {
            let word = makeWord(text, reading: reading, romaji: expected, location: 4)
            let corrected = HonbakoJapaneseCharacterReadings.units(for: word)
            #expect(corrected.count == 1)
            #expect(corrected.first?.text == text)
            #expect(corrected.first?.romaji == expected)
            #expect(corrected.first?.range == word.range)
            #expect(corrected.first?.wordID == word.id)
        }
        #expect(units("は").map(\.romaji) == ["ha"])
        #expect(units("へ").map(\.romaji) == ["he"])
        #expect(units("を").map(\.romaji) == ["wo"])
        #expect(units("はし").map(\.romaji) == ["ha", "shi"])
        let multiCharacter = makeWord("はし", reading: "わし", romaji: "washi")
        #expect(HonbakoJapaneseCharacterReadings.units(for: multiCharacter).map(\.romaji) == ["ha", "shi"],
                "A differing multi-character reading must not be guessed into glyph assignments")
    }

    @Test("Kanji use contextual spans rather than fabricated per-kanji readings")
    func contextualKanji() {
        let compound = HonbakoJapaneseCharacterReadings.units(for: makeWord("大人", reading: "おとな", romaji: "otona"))
        #expect(compound.map(\.text) == ["大人"])
        #expect(compound.map(\.romaji) == ["otona"])
        let inflected = HonbakoJapaneseCharacterReadings.units(for: makeWord("食べました", reading: "たべました", romaji: "tabemashita"))
        #expect(inflected.map(\.text) == ["食", "べ", "ま", "し", "た"])
        #expect(inflected.map(\.romaji) == ["ta", "be", "ma", "shi", "ta"])
        #expect(HonbakoJapaneseCharacterReadings.units(for: makeWord("𠮷", reading: nil, romaji: nil)).isEmpty)
    }

    @Test("Normalization never moves OCR anchors across emoji, halfwidth or combining marks")
    func sourceRanges() {
        for text in ["ｶﾀｶﾅ", "か\u{3099}く"] {
            let word = makeWord(text, reading: nil, romaji: nil, location: 2)
            for unit in HonbakoJapaneseCharacterReadings.units(for: word) {
                let local = NSRange(location: unit.range.location - 2, length: unit.range.length)
                #expect((text as NSString).substring(with: local) == unit.text)
                #expect(Range(local, in: text) != nil)
            }
        }
    }

    @Test("Both text axes use real distinct character boxes, never repeated line geometry")
    func exactCharacterAnchors() throws {
        for vertical in [false, true] {
            let parent = vertical ? CGRect(x: 0.5, y: 0.1, width: 0.1, height: 0.6)
                : CGRect(x: 0.1, y: 0.5, width: 0.6, height: 0.1)
            let boxes = (0..<3).map { index in
                vertical ? CGRect(x: 0.51, y: 0.12 + Double(index) * 0.18, width: 0.08, height: 0.15)
                    : CGRect(x: 0.12 + Double(index) * 0.18, y: 0.51, width: 0.15, height: 0.08)
            }
            let validated = HonbakoJapaneseWordGeometry.validatedCharacterBoxes(boxes, in: parent)
            #expect(validated.count == boxes.count)
            for (proposed, result) in zip(boxes, validated) {
                let actual = try #require(result)
                #expect(abs(actual.minX - proposed.minX) < 0.000000001)
                #expect(abs(actual.minY - proposed.minY) < 0.000000001)
                #expect(abs(actual.width - proposed.width) < 0.000000001)
                #expect(abs(actual.height - proposed.height) < 0.000000001)
                #expect(parent.contains(actual), "A retained glyph must remain inside the real text region")
            }
            #expect(HonbakoJapaneseWordGeometry.validatedCharacterBoxes([parent, parent, parent], in: parent).allSatisfy { $0 == nil })
        }
    }

    @Test("The original page exposes genuine Vision character anchors for inline kana readings")
    @MainActor
    func originalPracticeCharacterAnchors() async throws {
        let regions = try await HonbakoJapaneseTextRecognizer.recognize(image: HonbakoJapanesePracticePage.render())
        let sentence = try #require(regions.first { $0.text.contains("きょうもいっしょによもう") })
        #expect(sentence.characters.map(\.character.romaji) == ["kyo", "u", "mo", "i", "s", "sho", "ni", "yo", "mo", "u"])
        let anchored = sentence.characters.compactMap(\.boundingBox)
        #expect(anchored.count == sentence.characters.count, "Printed practice kana must have genuine per-character Vision boxes")
        #expect(anchored.allSatisfy { $0.width < sentence.boundingBox.width * 0.25 })
        #expect(sentence.characters.allSatisfy { $0.ink.red < 128 && $0.ink.green < 128 && $0.ink.blue < 128 })
    }

    private func units(_ text: String) -> [HonbakoJapaneseCharacterReading] {
        HonbakoJapaneseCharacterReadings.units(for: makeWord(text, reading: nil, romaji: nil))
    }

    private func makeWord(_ text: String, reading: String?, romaji: String?, location: Int = 0) -> HonbakoJapaneseWord {
        .init(id: location, text: text, reading: reading, romaji: romaji, readingIsEstimated: false,
              range: NSRange(location: location, length: (text as NSString).length))
    }
}
