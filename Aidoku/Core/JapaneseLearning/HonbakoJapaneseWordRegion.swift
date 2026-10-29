import CoreGraphics

struct HonbakoJapaneseWordRegion: Identifiable, Equatable, Sendable {
    var id: Int { word.id }
    let word: HonbakoJapaneseWord
    /// Actual Vision range geometry, normalized from the oriented page's top-left.
    /// Missing or ambiguous geometry stays nil rather than dividing a phrase box.
    let boundingBox: CGRect?
}
