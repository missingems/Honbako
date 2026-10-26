import Foundation
import CoreGraphics
import Testing
@testable import Sumi

struct SumiBookPileLayoutTests {
    @Test func savedPlacementSurvivesViewportChanges() throws {
        let layout = SumiBookPileLayout(count: 18)
        let original = layout.initialPlacement(id: "fixture:book-7", index: 7)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(SumiBookPilePlacement.self, from: data)
        // The model has no viewport parameter: opening/folding the device only
        // changes the camera and must not modify saved logical coordinates.
        #expect(layout.bounded(restored) == original)
        #expect(layout.initialPlacement(id: "fixture:book-7", index: 7) == original)
    }

    @Test func libraryShrinkAndCorruptCoordinatesStayInsideWalls() {
        let small = SumiBookPileLayout(count: 1)
        let large = SumiBookPileLayout(count: 200)
        let farAway = large.initialPlacement(id: "fixture:last", index: 199)
        for placement in [farAway, .init(x: .infinity, y: -.infinity, z: .nan, angle: .nan)] {
            let safe = small.bounded(placement)
            #expect(safe.x.isFinite && safe.y.isFinite && safe.z.isFinite && safe.angle.isFinite)
            #expect(abs(safe.x) + small.edgeClearance <= small.width / 2 + 0.0001)
            #expect(abs(safe.y) + small.edgeClearance <= small.height / 2 + 0.0001)
            #expect(safe.z >= SumiBookPileLayout.bookDepth / 2)
        }
    }

    @Test func throwsPreserveDirectionAndCapKineticEnergy() {
        let velocity = SumiBookPileLayout.throwVelocity(x: 300, y: -400)
        #expect(abs(hypot(velocity.dx, velocity.dy) - SumiBookPileLayout.maximumThrowSpeed) < 0.0001)
        #expect(abs(velocity.dx / velocity.dy + 0.75) < 0.0001)
        #expect(SumiBookPileLayout.throwVelocity(x: 2, y: 3) == .init(dx: 2, dy: 3))
        #expect(SumiBookPileLayout.throwVelocity(x: .nan, y: 2) == .zero)
    }
}
