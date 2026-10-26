#if SUMI
import Foundation
import CoreGraphics

/// Logical tabletop coordinates never depend on the window, display or fold.
/// Changing the viewport only changes the camera, not a user's arrangement.
struct SumiBookPileLayout {
    static let bookWidth = 1.64
    static let bookHeight = 2.38
    static let bookDepth = 0.20
    static let maximumThrowSpeed = 12.0

    let count: Int
    var columns: Int { max(2, Int(ceil(sqrt(Double(max(1, count)) * 0.9)))) }
    var rows: Int { max(1, Int(ceil(Double(max(1, count)) / Double(columns)))) }
    var width: Double { max(6.8, Double(columns - 1) * 1.94 + 4.3) }
    var height: Double { max(7.2, Double(rows - 1) * 2.64 + 4.8) }
    // A book can rotate through any angle without crossing the table's walls.
    var edgeClearance: Double { hypot(Self.bookWidth, Self.bookHeight) / 2 + 0.12 }

    func initialPlacement(id: String, index: Int) -> SumiBookPilePlacement {
        let seed = Self.seed(id)
        let xJitter = Double(seed % 101) / 100 - 0.5
        let yJitter = Double((seed >> 9) % 101) / 100 - 0.5
        let angle = (Double((seed >> 17) % 97) - 48) * .pi / 180
        let itemCountInRow = min(columns, max(1, count - (index / columns) * columns))
        let x = (Double(index % columns) - Double(itemCountInRow - 1) / 2) * 1.70 + xJitter * 1.20
        let y = (Double(rows - 1) / 2 - Double(index / columns)) * 2.30 + yJitter * 1.20
        return bounded(.init(x: x, y: y, z: 0.14 + Double(index % 4) * 0.23, angle: angle))
    }

    func bounded(_ placement: SumiBookPilePlacement) -> SumiBookPilePlacement {
        let xLimit = max(0, width / 2 - edgeClearance)
        let yLimit = max(0, height / 2 - edgeClearance)
        return .init(
            x: min(xLimit, max(-xLimit, placement.x.isFinite ? placement.x : 0)),
            y: min(yLimit, max(-yLimit, placement.y.isFinite ? placement.y : 0)),
            z: min(4, max(Self.bookDepth / 2 + 0.015, placement.z.isFinite ? placement.z : 0.12)),
            angle: placement.angle.isFinite ? placement.angle.remainder(dividingBy: 2 * .pi) : 0
        )
    }

    static func throwVelocity(x: Double, y: Double) -> CGVector {
        guard x.isFinite, y.isFinite else { return .zero }
        let length = hypot(x, y)
        let factor = length > maximumThrowSpeed ? maximumThrowSpeed / length : 1
        return CGVector(dx: x * factor, dy: y * factor)
    }

    private static func seed(_ id: String) -> UInt64 {
        id.utf8.reduce(UInt64(1_469_598_103_934_665_603)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}
#endif
