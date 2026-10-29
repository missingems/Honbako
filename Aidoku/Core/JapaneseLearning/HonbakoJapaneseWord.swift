import Foundation

/// One lexical Japanese word. Its range refers to the unchanged, trimmed source
/// text, never the normalized kana or romaji, so OCR anchors remain exact.
struct HonbakoJapaneseWord: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let reading: String?
    let romaji: String?
    let readingIsEstimated: Bool
    let range: NSRange
}
