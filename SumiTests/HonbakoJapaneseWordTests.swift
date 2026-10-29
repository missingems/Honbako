@testable import Sumi
import CoreGraphics
import Foundation
import Testing
import UIKit

@Suite struct HonbakoJapaneseWordTests {
    @Test("Kana-only dialogue gets Japanese words instead of one long romaji string")
    func kanaWords() {
        let reading = HonbakoJapaneseText.reading(for: "きょうもいっしょによもう。")
        #expect(reading.words.map(\.text) == ["きょう", "も", "いっしょ", "に", "よもう"])
        #expect(reading.words.map(\.romaji) == ["kyou", "mo", "issho", "ni", "yomou"])
        #expect(reading.words.allSatisfy { !$0.readingIsEstimated })
        #expect(reading.romaji?.contains("kyou mo issho ni yomou") == true)
        #expect(!reading.words.contains { $0.text == "。" })
    }

    @Test("Terminal punctuation does not split the common word あした into syllables")
    func punctuationBoundaries() {
        for source in ["またあした。", "「またあした。」", "  『またあした。』  "] {
            let reading = HonbakoJapaneseText.reading(for: source)
            #expect(reading.words.map(\.text) == ["また", "あした"])
            #expect(reading.words.map(\.romaji) == ["mata", "ashita"])
            for word in reading.words {
                #expect((reading.text as NSString).substring(with: word.range) == word.text)
                #expect(Range(word.range, in: reading.text) != nil)
            }
        }
    }

    @Test("Punctuation-only kanji context never substitutes Chinese pinyin for Japanese word readings")
    func japaneseKanjiWords() {
        let reading = HonbakoJapaneseText.reading(for: "猫、猫！")
        #expect(reading.words.map(\.text) == ["猫", "猫"])
        #expect(reading.words.map(\.romaji) == ["neko", "neko"])
        #expect(reading.reading == "ねこ、ねこ!")
        #expect(reading.romaji?.contains("māo") != true)
        #expect(reading.romaji?.contains("mao") != true)
        #expect(Set(reading.words.map(\.id)).count == 2)
        #expect(reading.words.allSatisfy { $0.readingIsEstimated })
        #expect(HonbakoJapaneseText.reading(for: "漢字").words.first?.romaji == "kanji")
    }

    @Test("Original UTF-16 ranges survive emoji, half-width kana, combining dakuten and supplementary kanji")
    func unicodeSourceRanges() throws {
        for input in ["  🙂ｶﾀｶﾅと、か\u{3099}くせい。  ", "𠮷野家で読む", "猫、猫！"] {
            let reading = HonbakoJapaneseText.reading(for: input)
            let source = reading.text as NSString
            #expect(!reading.words.isEmpty)
            #expect(Set(reading.words.map(\.id)).count == reading.words.count)
            for word in reading.words {
                #expect(word.range.location >= 0)
                #expect(NSMaxRange(word.range) <= source.length)
                #expect(source.substring(with: word.range) == word.text)
                #expect(Range(word.range, in: reading.text) != nil)
                #expect(word.id == word.range.location)
            }
        }
        let halfwidth = try #require(HonbakoJapaneseText.reading(for: "🙂ｶﾀｶﾅ").words.first)
        #expect(halfwidth.text == "ｶﾀｶﾅ")
        #expect(halfwidth.range == NSRange(location: 2, length: 4))
        #expect(halfwidth.reading == "かたかな")
        #expect(halfwidth.romaji == "katakana")
    }

    @Test("Empty and non-Japanese inputs do not create fake Japanese words")
    func excludesNonWords() {
        for text in ["", "  ", "Page 12", "🙂", "！。"] {
            #expect(HonbakoJapaneseText.reading(for: text).words.isEmpty)
        }
    }

    @Test("Whole-line or duplicated word geometry remains unanchored instead of guessing")
    func rejectsAmbiguousAnchors() throws {
        let words = HonbakoJapaneseText.reading(for: "猫と犬").words
        #expect(words.count >= 2)
        let parent = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.2)
        let duplicates = words.map { HonbakoJapaneseWordRegion(word: $0, boundingBox: parent) }
        #expect(HonbakoJapaneseWordGeometry.validated(duplicates, in: parent).allSatisfy { $0.boundingBox == nil })
        let repeatedBox = CGRect(x: 0.2, y: 0.12, width: 0.15, height: 0.15)
        let repeated = words.map { HonbakoJapaneseWordRegion(word: $0, boundingBox: repeatedBox) }
        #expect(HonbakoJapaneseWordGeometry.validated(repeated, in: parent).allSatisfy { $0.boundingBox == nil })
        let greeting = try #require(HonbakoJapaneseText.reading(for: "ありがとう").words.first)
        let single = HonbakoJapaneseWordGeometry.validated([.init(word: greeting, boundingBox: parent)], in: parent)
        let box = try #require(single.first?.boundingBox)
        #expect(abs(box.minX - parent.minX) < 0.000001)
        #expect(abs(box.minY - parent.minY) < 0.000001)
        #expect(abs(box.width - parent.width) < 0.000001)
        #expect(abs(box.height - parent.height) < 0.000001)
    }

    @Test("The original practice page has distinct genuine Vision anchors for each dialogue word")
    @MainActor
    func originalPracticeWordAnchors() async throws {
        let regions = try await HonbakoJapaneseTextRecognizer.recognize(image: HonbakoJapanesePracticePage.render())
        // This fixture is original generated text, never a user's page. Keep
        // compact diagnostics so range geometry can be compared across OS builds.
        for region in regions {
            let words: [[String: Any]] = region.words.map { item in
                var value: [String: Any] = ["text": item.word.text, "start": item.word.range.location, "length": item.word.range.length]
                if let box = item.boundingBox {
                    value["box"] = [box.minX, box.minY, box.width, box.height]
                }
                return value
            }
            let data = try JSONSerialization.data(withJSONObject: ["phrase": region.text, "words": words], options: [.sortedKeys])
            if let payload = String(data: data, encoding: .utf8) {
                print("HonbakoPracticeWordAnchors " + payload)
            }
        }
        let sentence = try #require(regions.first { $0.text.contains("きょうもいっしょによもう") })
        #expect(sentence.words.count >= 4)
        let anchored = sentence.words.compactMap(\.boundingBox)
        #expect(anchored.count >= 3, "The common practice sentence must have actual word locations")
        #expect(Set(anchored.map { "\($0.minX)|\($0.minY)|\($0.width)|\($0.height)" }).count == anchored.count)
        #expect(anchored.allSatisfy { sentence.boundingBox.contains($0) })
        #expect(anchored.allSatisfy { $0.width < sentence.boundingBox.width * 0.8 })
        for word in sentence.words {
            #expect((sentence.text as NSString).substring(with: word.word.range) == word.word.text)
        }
    }
}
