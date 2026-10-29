import CoreGraphics
import Foundation

struct HonbakoJapaneseReading: Equatable, Sendable {
    let text: String
    let reading: String?
    let romaji: String?
    let readingIsEstimated: Bool
    let words: [HonbakoJapaneseWord]

    init(text: String, reading: String?, romaji: String?, readingIsEstimated: Bool,
         words: [HonbakoJapaneseWord] = []) {
        self.text = text
        self.reading = reading
        self.romaji = romaji
        self.readingIsEstimated = readingIsEstimated
        self.words = words
    }
}

struct HonbakoJapaneseRegion: Identifiable, Equatable, Sendable {
    enum Direction: Sendable {
        case horizontal
        case vertical
        case unknown
    }

    let id: Int
    let text: String
    let reading: String?
    let romaji: String?
    let confidence: Float
    let readingIsEstimated: Bool
    let direction: Direction
    /// Relative to the oriented page image: origin is top-left and each axis is 0...1.
    let boundingBox: CGRect
    let words: [HonbakoJapaneseWordRegion]

    init(id: Int, text: String, reading: String?, romaji: String?, confidence: Float,
         readingIsEstimated: Bool, direction: Direction, boundingBox: CGRect,
         words: [HonbakoJapaneseWordRegion] = []) {
        self.id = id
        self.text = text
        self.reading = reading
        self.romaji = romaji
        self.confidence = confidence
        self.readingIsEstimated = readingIsEstimated
        self.direction = direction
        self.boundingBox = boundingBox
        self.words = words
    }
}
