#if SUMI
/// A coherent ruby row sits before or after its Japanese line or column.
enum HonbakoJapaneseOverlaySide: CaseIterable, Equatable, Sendable {
    case before
    case after

    static func preferred(for direction: HonbakoJapaneseRegion.Direction) -> [Self] {
        // Vertical Japanese reads down each column. Keep upright romaji on
        // its right, using the left only when artwork or the page edge blocks it.
        direction == .vertical ? [.after, .before] : [.before, .after]
    }
}
#endif
