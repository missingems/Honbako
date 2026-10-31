import CoreGraphics

struct HonbakoJapaneseCharacterRegion: Identifiable, Equatable, Sendable {
    var id: Int { character.id }
    let character: HonbakoJapaneseCharacterReading
    /// Real Vision glyph geometry; unavailable anchors are never interpolated.
    let boundingBox: CGRect?
    let ink: HonbakoJapaneseInk
}

struct HonbakoJapaneseInk: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    static let black = Self(red: 0, green: 0, blue: 0)
    static let white = Self(red: 255, green: 255, blue: 255)
}
