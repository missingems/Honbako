@testable import Sumi
import CoreGraphics
import Foundation
import Testing
import UIKit

@Suite struct HonbakoJapaneseTextTests {
    @Test("Empty and non-Japanese text never invent Japanese readings")
    func noJapanese() {
        for input in ["", "   \n", "Page 12", "123 ! ?", "🙂"] {
            let result = HonbakoJapaneseText.reading(for: input)
            #expect(result.reading == nil)
            #expect(result.romaji == nil)
            #expect(!result.readingIsEstimated)
        }
    }

    @Test("Kana is romanized without sending kanji through the Chinese Latin transform")
    func kanaTranscription() {
        let hiragana = HonbakoJapaneseText.reading(for: "ありがとう")
        #expect(hiragana.reading == "ありがとう")
        #expect(hiragana.romaji == "arigatou")
        #expect(!hiragana.readingIsEstimated)
        let katakana = HonbakoJapaneseText.reading(for: "カタカナ")
        #expect(katakana.reading == "かたかな")
        #expect(katakana.romaji == "katakana")
        let halfwidth = HonbakoJapaneseText.reading(for: "ｶﾀｶﾅ")
        #expect(halfwidth.reading == "かたかな")
        #expect(halfwidth.romaji == "katakana")
    }

    @Test("Kanji readings use the Japanese system dictionary and stay explicitly estimated")
    func kanjiTranscription() {
        let result = HonbakoJapaneseText.reading(for: "漢字")
        #expect(result.reading == "かんじ")
        #expect(result.romaji == "kanji")
        #expect(result.readingIsEstimated)
        let name = HonbakoJapaneseText.reading(for: "五条悟")
        #expect(name.readingIsEstimated)
        #expect(name.romaji?.contains("wǔ") != true)
        #expect(name.romaji?.contains("tiáo") != true)
    }

    @Test("Whitespace and punctuation remain part of the selected source text")
    func preservesSource() {
        let result = HonbakoJapaneseText.reading(for: "  猫、ありがとう！  ")
        #expect(result.text == "猫、ありがとう！")
        #expect(result.reading?.contains("、") == true)
        #expect(result.reading?.hasSuffix("!") == true)
        #expect(result.readingIsEstimated)
    }

    @Test("Overlay boxes flip Vision coordinates once and map into the displayed page")
    func overlayGeometry() throws {
        let box = try #require(HonbakoJapaneseGeometry.topLeftBox(
            fromVision: CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.2)
        ))
        #expect(abs(box.minY - 0.1) < 0.0001)
        let frame = try #require(HonbakoJapaneseGeometry.rect(for: box, in: CGRect(x: 30, y: 40, width: 200, height: 400)))
        #expect(abs(frame.minX - 50) < 0.0001)
        #expect(abs(frame.minY - 80) < 0.0001)
        #expect(abs(frame.width - 40) < 0.0001)
        #expect(abs(frame.height - 80) < 0.0001)
    }

    @Test("Invalid and out-of-page overlay coordinates cannot create stray targets")
    func rejectsInvalidBoxes() {
        let page = CGRect(x: 0, y: 0, width: 200, height: 400)
        for box in [CGRect.zero, .null, .infinite,
                    CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1),
                    CGRect(x: 0, y: 0, width: -1, height: 1),
                    CGRect(x: 2, y: 0, width: 1, height: 1)] {
            #expect(HonbakoJapaneseGeometry.rect(for: box, in: page) == nil)
        }
        let clipped = HonbakoJapaneseGeometry.rect(for: CGRect(x: -0.5, y: 0, width: 1, height: 1), in: page)
        #expect(clipped == CGRect(x: 0, y: 0, width: 100, height: 400))
        #expect(HonbakoJapaneseGeometry.rect(for: CGRect(x: 0, y: 0, width: 1, height: 1), in: .zero) == nil)
    }

    @Test("The original practice page produces Japanese phrases with anchored reading aids")
    @MainActor
    func recognizesOriginalPracticePage() async throws {
        let regions = try await HonbakoJapaneseTextRecognizer.recognize(image: HonbakoJapanesePracticePage.render())
        let text = regions.map(\.text).joined()
        #expect(text.contains("おはよう"))
        #expect(text.contains("きょうもいっしょによもう") || text.contains("またあした"))
        #expect(regions.contains { $0.romaji?.isEmpty == false })
        #expect(Set(regions.map(\.id)).count == regions.count)
        for region in regions {
            #expect((0...1).contains(region.confidence))
            #expect(HonbakoJapaneseGeometry.rect(
                for: region.boundingBox,
                in: CGRect(x: 0, y: 0, width: 1024, height: 1536)
            ) != nil)
        }
        #expect(regions.contains { $0.direction == .vertical && $0.text.contains("ありがとう") })
    }

    @Test("Canceling page recognition does not deliver an obsolete page result")
    @MainActor
    func recognitionCancellation() async throws {
        let image = HonbakoJapanesePracticePage.render()
        let work = Task { try await HonbakoJapaneseTextRecognizer.recognize(image: image) }
        work.cancel()
        do {
            _ = try await work.value
            Issue.record("A canceled guide scan delivered regions")
        } catch is CancellationError {
            // The old page's result cannot replace a later selection.
        }
    }

    @Test("EXIF orientation keeps a recognized phrase anchored to the visible top of the page")
    @MainActor
    func recognitionRespectsOrientation() async throws {
        let original = HonbakoJapanesePracticePage.render()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let upsideDown = UIGraphicsImageRenderer(size: original.size, format: format).image { output in
            output.cgContext.translateBy(x: original.size.width, y: original.size.height)
            output.cgContext.rotate(by: .pi)
            original.draw(in: CGRect(origin: .zero, size: original.size))
        }
        let cgImage = try #require(upsideDown.cgImage)
        let oriented = UIImage(cgImage: cgImage, scale: 1, orientation: .down)
        let regions = try await HonbakoJapaneseTextRecognizer.recognize(image: oriented)
        let greeting = try #require(regions.first { $0.text.contains("おはよう") })
        #expect(greeting.boundingBox.midY < 0.3)
        #expect(greeting.boundingBox.minX < 0.5)
    }

    @Test("Missing Vision directions use oriented pixel dimensions without guessing square glyphs")
    func infersVerticalPixelGeometry() {
        let tall = CGRect(x: 0.77, y: 0.55, width: 0.09, height: 0.34)
        #expect(HonbakoJapaneseGeometry.inferredDirection(
            for: tall, imageSize: CGSize(width: 1024, height: 1536), characterCount: 5
        ) == .vertical)
        #expect(HonbakoJapaneseGeometry.inferredDirection(
            for: CGRect(x: 0, y: 0, width: 0.3, height: 0.1),
            imageSize: CGSize(width: 600, height: 2000), characterCount: 3
        ) == .unknown)
        #expect(HonbakoJapaneseGeometry.inferredDirection(
            for: CGRect(x: 0.1, y: 0.1, width: 0.7, height: 0.05),
            imageSize: CGSize(width: 1024, height: 1536), characterCount: 12
        ) == .horizontal)
        #expect(HonbakoJapaneseGeometry.inferredDirection(
            for: tall, imageSize: CGSize(width: 1024, height: 1536), characterCount: 1
        ) == .unknown)
    }

}
