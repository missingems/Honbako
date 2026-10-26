@testable import Aidoku
import Testing

@Suite
struct ReaderBookPlanTests {
    @Test("Physical leaf order follows reading direction and odd tails contain one blank", arguments: [ReadingMode.ltr, .rtl])
    func physicalOrder(mode: ReadingMode) throws {
        let plan = ReaderBookPlan(canonicalGroups: [[1, 2], [3, 4], [5]], wideIndices: [], leadingBlankIndices: [], readingMode: mode)
        #expect(plan.groups.count == 3)
        #expect(plan.groups.allSatisfy { $0.count == 2 })
        #expect(plan.groups[0] == [.page(1), .page(2)])
        #expect(plan.physicalSlots(in: 0, readingMode: mode) == (mode == .rtl ? [.page(2), .page(1)] : [.page(1), .page(2)]))
        let tail = plan.physicalSlots(in: 2, readingMode: mode)
        #expect(tail.compactMap(\.canonicalIndex) == [5])
        #expect(tail.filter { $0.canonicalIndex == nil }.count == 1)
        #expect(tail[mode == .rtl ? 1 : 0] == .page(5))
        for (index, slots) in plan.groups.enumerated() {
            for slot in slots { #expect(plan.groupIndex(containing: slot) == index) }
        }
        #expect(plan.groupIndex(containingCanonicalIndex: 5) == 2)
        #expect(plan.groupIndex(containingCanonicalIndex: 99) == nil)
    }

    @Test("Wide physical image halves remain left/right in both reading directions", arguments: [ReadingMode.ltr, .rtl])
    func wideHalvesNeverMirror(mode: ReadingMode) throws {
        let plan = ReaderBookPlan(canonicalGroups: [[1], [2], [3, 4]], wideIndices: [2], leadingBlankIndices: [], readingMode: mode)
        let wideGroup = try #require(plan.groupIndex(containingCanonicalIndex: 2))
        #expect(plan.groups[wideGroup] == (mode == .rtl ? [.wideRight(2), .wideLeft(2)] : [.wideLeft(2), .wideRight(2)]))
        #expect(plan.physicalSlots(in: wideGroup, readingMode: mode) == [.wideLeft(2), .wideRight(2)])
        #expect(plan.groups[wideGroup].compactMap(\.canonicalIndex) == [2, 2])
        #expect(plan.groupIndex(containing: .wideLeft(2)) == wideGroup)
        #expect(plan.groupIndex(containing: .wideRight(2)) == wideGroup)
    }

    @Test("Offset covers put the blank before the first reading leaf", arguments: [ReadingMode.ltr, .rtl])
    func offsetCover(mode: ReadingMode) throws {
        let plan = ReaderBookPlan(canonicalGroups: [[1], [2, 3]], wideIndices: [], leadingBlankIndices: [1], readingMode: mode)
        let cover = plan.groups[0]
        #expect(cover.count == 2)
        #expect(cover[0].canonicalIndex == nil)
        #expect(cover[1] == .page(1))
        let physical = plan.physicalSlots(in: 0, readingMode: mode)
        #expect(physical[mode == .rtl ? 0 : 1] == .page(1))
        #expect(plan.physicalSlots(in: 1, readingMode: mode) == (mode == .rtl ? [.page(3), .page(2)] : [.page(2), .page(3)]))
    }

    @Test("Native adjacent slot lookups are reversible across leaves, blanks and wide halves", arguments: [ReadingMode.ltr, .rtl])
    func adjacencyRoundTrips(mode: ReadingMode) {
        let plan = ReaderBookPlan(canonicalGroups: [[0], [1], [2], [3, 4], [5]], wideIndices: [2], leadingBlankIndices: [1], readingMode: mode)
        let all = plan.groups.flatMap { $0 }
        #expect(Set(all).count == all.count)
        var traversedEdges = 0
        for slot in all {
            if let after = plan.adjacentSlot(to: slot, after: true, readingMode: mode) {
                #expect(plan.adjacentSlot(to: after, after: false, readingMode: mode) == slot)
                traversedEdges += 1
            }
            if let before = plan.adjacentSlot(to: slot, after: false, readingMode: mode) {
                #expect(plan.adjacentSlot(to: before, after: true, readingMode: mode) == slot)
            }
        }
        #expect(traversedEdges == all.count - 1)
    }
}
